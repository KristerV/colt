defmodule Colt.Services.Ingest.Se.Bolagsverket.AnnualReports do
  @moduledoc """
  Walks Bolagsverket's HVD document API for each Swedish company we have
  locally and writes one `Colt.Resources.AnnualReport` per (company, FY)
  with revenue (converted SEK→EUR) and average employees.

  Per-company flow:
    1. `POST /dokumentlista` with the org number → list of annual-report
       filings (filing ID, format, FY end).
    2. For each iXBRL filing within the configured year window:
       `GET /dokument/{id}` → raw iXBRL XML.
    3. Parse `se-gen-base:Nettoomsattning` (revenue) and
       `se-gen-base:MedelantaletAnstallda` (avg employees).
    4. Bulk-insert via raw SQL `INSERT … ON CONFLICT DO NOTHING`.

  The parser is intentionally separate from `Fi.Prh.AnnualReports.parse_xbrl/2`:
  the SE taxonomy uses descriptive element names without the MCY dimension
  layer, so the FI regex pipeline doesn't apply. ~80 LOC of duplicate
  XML walking is cheaper than a shared abstraction that fits neither.

  SEK → EUR conversion uses a fixed module constant (~mid-2026 rate).
  Revenue accuracy isn't load-bearing for B2B prospecting filters
  (10× growth buckets); revisit if FX accuracy ever matters.

  Run-shaping:
    * `Application.get_env(:colt, :ingest_max_years, 3)` — how many
      most-recent FY ends to keep per company.
    * `Application.get_env(:colt, :bolagsverket_se_max_filings, nil)` —
      total filings cap per run (dev/slice).
  """

  require Logger

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @list_url "https://gw.api.bolagsverket.se/vardefulla-datamangder/v1/dokumentlista"
  @doc_url "https://gw.api.bolagsverket.se/vardefulla-datamangder/v1/dokument"
  @page_size 200

  # Mid-2026 SEK/EUR. Not load-bearing — see moduledoc.
  @sek_eur 0.088

  def run(token) when is_binary(token) do
    with {:ok, companies} <- list_companies(),
         {:ok, count} <- ingest_companies(token, companies) do
      {:ok, %{processed: count}}
    end
  end

  defp list_companies do
    companies =
      :se
      |> Company.list_by_market!()
      |> Enum.map(&%{id: &1.id, registry_code: &1.registry_code})
      |> Enum.filter(&Sample.included?(&1.registry_code))

    Logger.info("BV annual reports: #{length(companies)} candidate companies")
    {:ok, companies}
  end

  defp ingest_companies(token, companies) do
    cap = Application.get_env(:colt, :bolagsverket_se_max_filings)
    target_years = target_years()

    {total, _remaining} =
      Enum.reduce_while(companies, {0, cap}, fn company, {acc, cap} ->
        if cap == 0 do
          {:halt, {acc, 0}}
        else
          n = ingest_company(token, company, target_years, cap)
          new_cap = if cap, do: max(cap - n, 0), else: nil
          {:cont, {acc + n, new_cap}}
        end
      end)

    Progress.done("BV annual reports upserted", total)
    {:ok, total}
  end

  defp target_years do
    max_years = Application.get_env(:colt, :ingest_max_years, 3)
    today = Date.utc_today()
    most_recent = if today.month >= 7, do: today.year - 1, else: today.year - 2
    Enum.to_list(most_recent..(most_recent - max_years + 1)//-1)
  end

  defp ingest_company(token, company, target_years, cap) do
    case list_filings(token, company.registry_code) do
      {:ok, filings} ->
        filings
        |> Enum.filter(&relevant_filing?(&1, target_years))
        |> maybe_take(cap)
        |> Enum.map(&fetch_and_parse(token, company, &1))
        |> Enum.reject(&is_nil/1)
        |> bulk_insert_ignore()

      :error ->
        0
    end
  end

  defp maybe_take(list, nil), do: list
  defp maybe_take(list, n), do: Enum.take(list, n)

  defp relevant_filing?(%{format: fmt, year: y}, years)
       when is_integer(y),
       do: fmt == :ixbrl and y in years

  defp relevant_filing?(_, _), do: false

  defp list_filings(token, code) do
    case Req.post(@list_url,
           headers: [
             {"authorization", "Bearer #{token}"},
             {"content-type", "application/json"}
           ],
           json: %{
             "organisationsidentitet" => %{"identitetsbeteckning" => code},
             "sokresultatPerSida" => @page_size
           },
           receive_timeout: 60_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: body}} ->
        items =
          body
          |> Map.get("dokument", [])
          |> Enum.map(&map_filing/1)
          |> Enum.reject(&is_nil/1)

        {:ok, items}

      other ->
        Logger.debug("BV dokumentlista fail code=#{code}: #{inspect(other)}")
        :error
    end
  end

  defp map_filing(item) do
    id = item["dokument_id"] || item["id"]
    period = item["rapporteringsperiod_tom"] || item["periodSlutdatum"]
    format = item["filformat"] || item["format"]

    with true <- is_binary(id) and id != "",
         year when is_integer(year) <- parse_year(period) do
      %{id: :binary.copy(id), year: year, format: normalise_format(format)}
    else
      _ -> nil
    end
  end

  defp normalise_format(fmt) when is_binary(fmt) do
    case String.downcase(fmt) do
      "ixbrl" -> :ixbrl
      "ix" -> :ixbrl
      "xhtml" -> :ixbrl
      _ -> :other
    end
  end

  defp normalise_format(_), do: :other

  defp parse_year(<<y::binary-size(4), _::binary>>), do: String.to_integer(y)
  defp parse_year(_), do: nil

  defp fetch_and_parse(token, company, filing) do
    case Req.get("#{@doc_url}/#{filing.id}",
           headers: [{"authorization", "Bearer #{token}"}],
           receive_timeout: 60_000,
           retry: false,
           decode_body: false
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case parse_xbrl(body) do
          %{revenue_sek: nil} ->
            nil

          %{revenue_sek: rev, employees: emp} ->
            %{
              company_id: company.id,
              year: filing.year,
              revenue_eur: sek_to_eur(rev),
              employees: emp,
              source: :bolagsverket
            }
        end

      _ ->
        nil
    end
  end

  defp sek_to_eur(nil), do: nil

  defp sek_to_eur(%Decimal{} = sek) do
    sek
    |> Decimal.mult(Decimal.from_float(@sek_eur))
    |> Decimal.round(0)
  end

  # ---- iXBRL extraction (regex-based; SE taxonomy uses direct element names) ----
  # Facts are tagged inline as `<ix:nonFraction name="se-gen-base:Nettoomsattning"
  # contextRef="..." unitRef="..." decimals="...">12345</ix:nonFraction>`.
  # We pull the value and the contextRef, then resolve the contextRef to
  # an endDate so we keep only current-period facts (not the prior-year
  # comparative).

  @fact_re ~r/<ix:nonFraction\b[^>]*\bname="se-gen-base:(Nettoomsattning|MedelantaletAnstallda)"[^>]*\bcontextRef="([^"]+)"[^>]*>([^<]+)<\/ix:nonFraction>/

  @context_re ~r/<(?:xbrli:)?context\b[^>]*\bid="([^"]+)"[^>]*>(.*?)<\/(?:xbrli:)?context>/s
  @period_end_re ~r/<(?:xbrli:)?(?:instant|endDate)>([\d-]+)<\/(?:xbrli:)?(?:instant|endDate)>/

  @doc """
  Extract `{revenue_sek, employees}` from one iXBRL filing.
  Returns the most recent dated period when multiple are present.
  """
  def parse_xbrl(xml) when is_binary(xml) do
    ctx_end =
      Regex.scan(@context_re, xml, capture: :all_but_first)
      |> Enum.reduce(%{}, fn [cid, body], acc ->
        case Regex.run(@period_end_re, body, capture: :all_but_first) do
          [period_end] -> Map.put(acc, :binary.copy(cid), :binary.copy(period_end))
          _ -> acc
        end
      end)

    Regex.scan(@fact_re, xml, capture: :all_but_first)
    |> Enum.reduce(%{revenue_sek: nil, employees: nil, period: nil}, fn
      [concept, cid, raw], acc ->
        period = Map.get(ctx_end, cid)
        merge_fact(acc, concept, raw, period)
    end)
    |> Map.take([:revenue_sek, :employees])
  end

  # Only retain the latest period (we want current FY, not comparatives).
  defp merge_fact(acc, concept, raw, period) do
    cond do
      is_nil(period) ->
        acc

      acc.period == nil or period > acc.period ->
        seed = %{revenue_sek: nil, employees: nil, period: period}
        Map.merge(seed, fact_value(concept, raw))

      period == acc.period ->
        Map.merge(acc, fact_value(concept, raw))

      true ->
        acc
    end
  end

  defp fact_value("Nettoomsattning", raw) do
    %{revenue_sek: parse_decimal(raw) |> abs_decimal()}
  end

  defp fact_value("MedelantaletAnstallda", raw) do
    %{employees: parse_employees(raw)}
  end

  defp parse_decimal(s) when is_binary(s) do
    cleaned = s |> String.replace(~r/[\s\xA0]/u, "")

    case Decimal.parse(cleaned) do
      {dec, _} -> dec
      :error -> nil
    end
  end

  defp parse_decimal(_), do: nil

  defp abs_decimal(nil), do: nil
  defp abs_decimal(%Decimal{} = d), do: Decimal.abs(d)

  defp parse_employees(s) when is_binary(s) do
    case Float.parse(String.replace(s, ~r/[\s\xA0,]/u, "")) do
      {f, _} when f >= 0 -> trunc(Float.round(f))
      _ -> nil
    end
  end

  defp parse_employees(_), do: nil

  # ---- bulk insert (raw SQL unnest + ON CONFLICT DO NOTHING) ----

  defp bulk_insert_ignore([]), do: 0

  defp bulk_insert_ignore(rows) do
    # The same (company, year) can appear twice if a filing was amended;
    # dedupe within a batch so Postgres doesn't reject the multi-row insert.
    deduped = Enum.uniq_by(rows, &{&1.company_id, &1.year})
    count = length(deduped)
    now = DateTime.utc_now()

    ids = Enum.map(deduped, fn _ -> Ecto.UUID.bingenerate() end)
    company_ids = Enum.map(deduped, &Ecto.UUID.dump!(&1.company_id))
    years = Enum.map(deduped, & &1.year)
    revenues = Enum.map(deduped, & &1.revenue_eur)
    employees = Enum.map(deduped, & &1.employees)
    sources = Enum.map(deduped, &Atom.to_string(&1.source))
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

    {:ok, _} =
      Ecto.Adapters.SQL.query(
        Colt.Repo,
        sql,
        [ids, company_ids, years, revenues, employees, sources, timestamps, timestamps]
      )

    count
  end
end
