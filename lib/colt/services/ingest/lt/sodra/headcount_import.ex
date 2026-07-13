defmodule Colt.Services.Ingest.Lt.Sodra.HeadcountImport do
  @moduledoc """
  Streams the `apdraustieji_det.zip` archive from Sodra, picks the
  **latest month per (employer code, fiscal_year)**, and upserts
  `AnnualReport.employees` for each Lithuanian company.

  ## Schema verification status

  As documented in `docs/countries/lt.md`, the Cloudflare blocker on
  `atvira.sodra.lt` prevented Phase A from downloading a real sample.
  The parser below assumes the column layout published in Sodra's data
  dictionary (`https://atvira.sodra.lt/imones/rinkiniai/index.html`):

      ju_kodas;ju_pavadinimas;ataskaitinis_laikotarpis;apdraustuju_sk;vidutinis_du

  - `ju_kodas` — legal-entity code (matches `Company.registry_code` for `:lt`)
  - `ataskaitinis_laikotarpis` — reporting period `YYYY-MM`
  - `apdraustuju_sk` — number of insured persons (= effective headcount)
  - `vidutinis_du` — average wage (EUR, not stored today)

  If the real file uses different headers, only the constants in
  `@field_*` below need to change; the rest of the pipeline is generic.

  ## Year resolution

  Sodra publishes monthly snapshots. We pick the **last available month
  per (employer, calendar year)** as the year's headcount — same shape
  as a year-end average. This avoids two `AnnualReport` rows when the
  same employer has January and December counts.

  ## UPSERT semantics

  Existing `AnnualReport` rows for `(company_id, year)` come from RC and
  carry `revenue_eur` with `employees = nil`. We:

      INSERT … ON CONFLICT (company_id, year) DO UPDATE
        SET employees = EXCLUDED.employees,
            source    = CASE WHEN annual_reports.revenue_eur IS NULL
                             THEN EXCLUDED.source
                             ELSE annual_reports.source END,
            updated_at = EXCLUDED.updated_at

  i.e. headcount always wins (since RC never has one); the `source`
  stays `:rc` when revenue is present, becomes `:sodra` for years where
  no RC filing exists. Single-field provenance is a known limitation —
  see "Open follow-ups" in the country plan.
  """

  require Logger

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @filename "apdraustieji_det.zip"
  @batch 1000

  # Column names — adjust here if Sodra's real schema differs.
  @field_code "ju_kodas"
  @field_period "ataskaitinis_laikotarpis"
  @field_count "apdraustuju_sk"

  def run(path \\ nil) do
    with {:ok, path} <- locate_file(path),
         {:ok, member} <- pick_csv_member(path),
         {:ok, by_code} <- index_companies(),
         {:ok, count} <- stream_and_upsert(path, member, by_code) do
      {:ok, %{processed: count}}
    end
  end

  # Explicit path (e.g. an admin-uploaded ZIP) bypasses the cache dir.
  defp locate_file(path) when is_binary(path) do
    if File.exists?(path), do: {:ok, path}, else: {:error, {:not_found, path}}
  end

  defp locate_file(nil) do
    dir = Application.fetch_env!(:colt, :sodra_lt_cache_dir)
    path = Path.join(dir, @filename)
    if File.exists?(path), do: {:ok, path}, else: {:error, {:not_found, path}}
  end

  defp pick_csv_member(zip_path) do
    case :zip.list_dir(String.to_charlist(zip_path)) do
      {:ok, entries} ->
        csv =
          Enum.find_value(entries, fn
            {:zip_file, name, _, _, _, _} ->
              name_str = to_string(name)
              if String.ends_with?(String.downcase(name_str), ".csv"), do: name_str

            _ ->
              nil
          end)

        if csv, do: {:ok, csv}, else: {:error, :no_csv_in_zip}

      {:error, reason} ->
        {:error, {:zip_list_failed, reason}}
    end
  end

  defp index_companies do
    companies =
      Company
      |> Ash.Query.for_read(:list_by_market, %{market: :lt})
      |> Ash.Query.select([:id, :registry_code])
      |> Ash.read!()

    {:ok, Map.new(companies, &{&1.registry_code, &1.id})}
  end

  defp stream_and_upsert(zip_path, member, by_code) do
    {:ok, [{_, csv_bytes}]} =
      :zip.unzip(String.to_charlist(zip_path),
        file_list: [String.to_charlist(member)],
        memory: true
      )

    [header_line | rest] = csv_bytes |> :erlang.iolist_to_binary() |> String.split(~r/\r?\n/)
    headers = parse_csv_line(header_line)

    {idx_code, idx_period, idx_count} = resolve_indexes(headers)

    # Build latest-per-(code, year) headcount in a map. The zip's CSV is
    # typically sorted by code then period; we still build a global map
    # because the file is bounded (~hundreds of MB unpacked at most)
    # and the value is a single integer per pair.
    latest =
      rest
      |> Stream.reject(&(&1 == ""))
      |> Progress.tick("Sodra rows read")
      |> Stream.map(&parse_csv_line/1)
      |> Stream.map(&extract(&1, idx_code, idx_period, idx_count))
      |> Stream.reject(&is_nil/1)
      |> Stream.filter(&Sample.included?(&1.registry_code))
      |> Enum.reduce(%{}, fn row, acc ->
        key = {row.registry_code, row.year}

        Map.update(acc, key, row, fn existing ->
          if row.period_sortable >= existing.period_sortable, do: row, else: existing
        end)
      end)

    count =
      latest
      |> Stream.flat_map(fn {{code, year}, row} ->
        case Map.get(by_code, code) do
          nil -> []
          company_id -> [%{company_id: company_id, year: year, employees: row.count}]
        end
      end)
      |> Stream.chunk_every(@batch)
      |> Enum.reduce(0, fn chunk, n ->
        bulk_upsert(chunk)
        n + length(chunk)
      end)

    Progress.done("Sodra headcounts upserted", count)
    {:ok, count}
  end

  defp resolve_indexes(headers) do
    idx_code = Enum.find_index(headers, &(&1 == @field_code))
    idx_period = Enum.find_index(headers, &(&1 == @field_period))
    idx_count = Enum.find_index(headers, &(&1 == @field_count))

    if is_nil(idx_code) or is_nil(idx_period) or is_nil(idx_count) do
      raise "Sodra CSV missing expected columns. Got: #{inspect(headers)}"
    end

    {idx_code, idx_period, idx_count}
  end

  defp extract(fields, idx_code, idx_period, idx_count) do
    with code when code not in [nil, ""] <- Enum.at(fields, idx_code) |> String.trim(),
         period when period not in [nil, ""] <- Enum.at(fields, idx_period) |> String.trim(),
         count_str when count_str not in [nil, ""] <- Enum.at(fields, idx_count) |> String.trim(),
         <<year_bin::binary-size(4), rest::binary>> <- period,
         {year, ""} <- Integer.parse(year_bin) do
      %{
        registry_code: :binary.copy(code),
        year: year,
        period_sortable: period_sortable(period),
        count: parse_int(count_str),
        _trailing: rest
      }
    else
      _ -> nil
    end
  end

  defp period_sortable(period) do
    period
    |> String.replace(["-", "/", "."], "")
    |> String.slice(0, 6)
    |> Integer.parse()
    |> case do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  # Sodra publishes CSVs with `;` separator (typical for LT/EE
  # municipal data). Strip surrounding quotes per field.
  defp parse_csv_line(line) do
    line
    |> String.trim_trailing("\r")
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&unquote_field/1)
  end

  defp unquote_field(<<?", rest::binary>>) when byte_size(rest) >= 1 do
    case :binary.last(rest) do
      ?" -> :binary.part(rest, 0, byte_size(rest) - 1)
      _ -> "\"" <> rest
    end
  end

  defp unquote_field(s), do: s

  defp bulk_upsert([]), do: 0

  defp bulk_upsert(rows) do
    count = length(rows)
    now = DateTime.utc_now()

    ids = Enum.map(rows, fn _ -> Ecto.UUID.bingenerate() end)
    company_ids = Enum.map(rows, &Ecto.UUID.dump!(&1.company_id))
    years = Enum.map(rows, & &1.year)
    revenues = List.duplicate(nil, count)
    employees = Enum.map(rows, & &1.employees)
    sources = List.duplicate("sodra", count)
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
    ON CONFLICT (company_id, year) DO UPDATE
      SET employees  = EXCLUDED.employees,
          source     = CASE
                         WHEN annual_reports.revenue_eur IS NULL
                         THEN EXCLUDED.source
                         ELSE annual_reports.source
                       END,
          updated_at = EXCLUDED.updated_at
    """

    {:ok, %{num_rows: affected}} =
      Ecto.Adapters.SQL.query(
        Colt.Repo,
        sql,
        [ids, company_ids, years, revenues, employees, sources, timestamps, timestamps]
      )

    affected
  end
end
