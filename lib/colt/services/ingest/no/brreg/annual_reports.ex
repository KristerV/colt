defmodule Colt.Services.Ingest.No.Brreg.AnnualReports do
  @moduledoc """
  Builds `Colt.Resources.AnnualReport` rows for Norwegian AS companies with
  filed annual accounts.

  Pipeline:

  1. Re-stream `enheter_alle.csv` to find every AS where
     `sisteInnsendteAarsregnskap` is populated, capturing `antallAnsatte` per
     orgnr (BRREG's regnskap API has no employee field; employees live only
     in the enhetsregister).
  2. `Task.async_stream` GETs `data.brreg.no/regnskapsregisteret/regnskap/{orgnr}`,
     25-way concurrency. Each response is an array of yearly filings.
  3. Filter to `regnskapstype: "SELSKAP"`, drop non-NOK / non-EUR records
     (no invented FX), keep `sumDriftsinntekter > 0`.
  4. Convert NOK → EUR via `@nok_per_eur`, document the rate in
     `docs/countries/no.md`.
  5. Stamp `antallAnsatte` onto the most recent fiscal year only.
  6. Resolve orgnr → company UUID via `Company.ids_by_codes!(:no, codes)`
     per 500-row chunk, then raw-SQL `unnest(...) ON CONFLICT DO NOTHING`
     insert into `annual_reports` with `source: :brreg`.
  """

  require Logger

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.No.Brreg.CompaniesImport.CSV
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @filename "enheter_alle.csv"
  @regnskap_base "https://data.brreg.no/regnskapsregisteret/regnskap"
  @concurrency 25
  @insert_chunk 500
  # Norges Bank annual avg 2024; review yearly. See docs/countries/no.md.
  @nok_per_eur Decimal.new("11.7")

  def run(opts \\ []) do
    limit = Keyword.get(opts, :limit)

    with {:ok, path} <- locate_file(),
         {:ok, candidates} <- stream_candidates(path, limit),
         {:ok, count} <- fetch_and_insert(candidates) do
      {:ok, %{processed: count}}
    end
  end

  defp locate_file do
    dir = Application.fetch_env!(:colt, :brreg_no_cache_dir)
    path = Path.join(dir, @filename)
    if File.exists?(path), do: {:ok, path}, else: {:error, {:not_found, path}}
  end

  # ---- stage 1: build candidate list (orgnr + antallAnsatte) ----

  defp stream_candidates(path, limit) do
    headers = read_headers(path)
    idx = column_index(headers)

    stream =
      path
      |> File.stream!(read_ahead: 256 * 1024)
      |> CSV.parse_stream(skip_headers: true)
      |> Stream.map(&parse_candidate(&1, idx))
      |> Stream.reject(&is_nil/1)
      |> Stream.filter(&Sample.included?(&1.registry_code))

    stream = if limit, do: Stream.take(stream, limit), else: stream

    list = Enum.to_list(stream)
    Logger.info("BRREG annual_reports candidates: #{length(list)}")
    {:ok, list}
  end

  defp parse_candidate(fields, idx) do
    code = at(fields, idx, "organisasjonsnummer")
    form = at(fields, idx, "organisasjonsform.kode")
    last = at(fields, idx, "sisteInnsendteAarsregnskap")

    cond do
      blank?(code) -> nil
      form != "AS" -> nil
      blank?(last) -> nil
      true -> %{registry_code: code, employees: parse_int(at(fields, idx, "antallAnsatte"))}
    end
  end

  defp read_headers(path) do
    path
    |> File.stream!()
    |> Enum.take(1)
    |> case do
      [line] -> line |> CSV.parse_string(skip_headers: false) |> List.first() || []
      [] -> []
    end
  end

  defp column_index(headers) do
    keep = ~w(organisasjonsnummer organisasjonsform.kode sisteInnsendteAarsregnskap antallAnsatte)

    headers
    |> Enum.with_index()
    |> Enum.into(%{})
    |> Map.take(keep)
  end

  # ---- stage 2-6: fan-out fetch, parse, batched insert ----

  defp fetch_and_insert(candidates) do
    total =
      candidates
      |> Task.async_stream(&fetch_one/1,
        max_concurrency: @concurrency,
        timeout: 60_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Stream.flat_map(fn
        {:ok, rows} when is_list(rows) -> rows
        _ -> []
      end)
      |> Progress.tick("BRREG regnskap rows parsed")
      |> Stream.chunk_every(@insert_chunk)
      |> Enum.reduce(0, fn chunk, n ->
        n + bulk_insert(chunk)
      end)

    Progress.done("BRREG annual_reports inserted", total)
    {:ok, total}
  end

  defp fetch_one(%{registry_code: code, employees: employees}) do
    url = "#{@regnskap_base}/#{code}"

    case Req.get(url,
           retry: false,
           receive_timeout: 30_000,
           connect_options: [timeout: 10_000]
         ) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        rows_for(code, employees, body)

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, list} when is_list(list) -> rows_for(code, employees, list)
          _ -> []
        end

      _ ->
        []
    end
  rescue
    e ->
      Logger.debug("BRREG regnskap fetch crashed for #{code}: #{Exception.message(e)}")
      []
  catch
    :exit, _ -> []
  end

  defp rows_for(code, employees, entries) do
    parsed =
      entries
      |> Enum.map(&parse_entry(code, &1))
      |> Enum.reject(&is_nil/1)

    case parsed do
      [] ->
        []

      list ->
        latest_year = list |> Enum.map(& &1.year) |> Enum.max()

        Enum.map(list, fn row ->
          if row.year == latest_year do
            %{row | employees: employees}
          else
            row
          end
        end)
    end
  end

  defp parse_entry(code, %{} = entry) do
    with "SELSKAP" <- get_in(entry, ["regnskapstype"]),
         tilDato when is_binary(tilDato) <- get_in(entry, ["regnskapsperiode", "tilDato"]),
         year when is_integer(year) <- year_of(tilDato),
         revenue when is_number(revenue) and revenue > 0 <-
           get_in(entry, [
             "resultatregnskapResultat",
             "driftsresultat",
             "driftsinntekter",
             "sumDriftsinntekter"
           ]),
         {:ok, eur} <- to_eur(revenue, entry["valuta"]) do
      %{registry_code: code, year: year, revenue_eur: eur, employees: nil}
    else
      _ -> nil
    end
  end

  defp parse_entry(_code, _other), do: nil

  defp year_of(<<y::binary-size(4), _::binary>>), do: String.to_integer(y)
  defp year_of(_), do: nil

  defp to_eur(amount, "EUR"), do: {:ok, Decimal.from_float(amount * 1.0) |> Decimal.round(2)}

  defp to_eur(amount, "NOK") do
    eur = Decimal.from_float(amount * 1.0) |> Decimal.div(@nok_per_eur) |> Decimal.round(2)
    {:ok, eur}
  end

  defp to_eur(_, _), do: :skip

  # ---- raw-SQL insert ----

  defp bulk_insert([]), do: 0

  defp bulk_insert(rows) do
    codes = Enum.map(rows, & &1.registry_code) |> Enum.uniq()

    id_by_code =
      Company.ids_by_codes!(:no, codes)
      |> Map.new(&{&1.registry_code, &1.id})

    resolved =
      rows
      |> Enum.filter(&Map.has_key?(id_by_code, &1.registry_code))
      |> Enum.map(fn row -> Map.put(row, :company_id, id_by_code[row.registry_code]) end)

    insert_rows(resolved)
  end

  defp insert_rows([]), do: 0

  defp insert_rows(rows) do
    count = length(rows)
    now = DateTime.utc_now()

    ids = Enum.map(rows, fn _ -> Ecto.UUID.bingenerate() end)
    company_ids = Enum.map(rows, &Ecto.UUID.dump!(&1.company_id))
    years = Enum.map(rows, & &1.year)
    revenues = Enum.map(rows, & &1.revenue_eur)
    employees = Enum.map(rows, & &1.employees)
    sources = List.duplicate("brreg", count)
    timestamps = List.duplicate(now, count)

    sql = """
    INSERT INTO annual_reports
      (id, company_id, year, revenue_eur, employees, source, inserted_at, updated_at)
    SELECT * FROM unnest(
      $1::uuid[],
      $2::uuid[],
      $3::int[],
      $4::numeric[],
      $5::int[],
      $6::text[],
      $7::timestamptz[],
      $8::timestamptz[]
    )
    ON CONFLICT (company_id, year) DO NOTHING
    """

    {:ok, %{num_rows: inserted}} =
      Ecto.Adapters.SQL.query(
        Colt.Repo,
        sql,
        [ids, company_ids, years, revenues, employees, sources, timestamps, timestamps]
      )

    inserted
  end

  # ---- helpers ----

  defp at(fields, idx, key) do
    case Map.get(idx, key) do
      nil -> nil
      n -> Enum.at(fields, n)
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, _} -> n
      :error -> nil
    end
  end
end
