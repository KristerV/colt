defmodule Colt.Services.Ingest.Dk.Cvr.AnnualReports do
  @moduledoc """
  Walks the public `distribution.virk.dk/offentliggoerelser` Elasticsearch
  scroll for the last `ingest_max_years` fiscal years and, for each hit,
  fetches the XBRL document at `regnskaber.virk.dk` and writes:

    * a `Colt.Resources.Company` row (identity + name + region from the
      XBRL gsd: header — there is no industry source in the free feed)
    * a `Colt.Resources.AnnualReport` row when `fsa:Revenue` or
      `fsa:AverageNumberOfEmployees` is present

  Coverage realities (verified 2026-05 on a 26-filing sample of FY2024
  reports):

    * Name + CVR: 100%
    * AverageNumberOfEmployees: ~81%
    * fsa:Revenue: ~12% (Class C+ and IFRS filers only; Class B SMEs
      legally hide Revenue and report only GrossProfitLoss, which is a
      different concept and is NOT used as a Revenue substitute)

  Currency: XBRL monetary facts are in DKK. We convert to EUR at a fixed
  module-attribute rate; DKK is pegged to EUR under ERM II so the drift
  is tiny. See `docs/countries/dk.md` for the full coverage write-up
  and the rationale for not back-filling Revenue from GrossProfit.

  Bulk path: raw SQL `INSERT … ON CONFLICT DO NOTHING` per
  `docs/large-csv-ingest.md`. Companies and reports are inserted with
  separate chunked statements so a partial XBRL parse failure can't
  leave an orphan report row.

  Per-run knobs (env-driven, never hard-coded into prod cron):

    * `Application.get_env(:colt, :ingest_max_years, 3)` — how many
      most-recent FY ends to walk.
    * `Application.get_env(:colt, :cvr_dk_max_filings, nil)` — cap total
      filings per run. Set in dev / verification slices.

  Override via `run(max_filings: 1000, max_years: 1)` for ad-hoc slices.
  """

  require Logger

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @scroll_url "http://distribution.virk.dk/offentliggoerelser/_search"
  @scroll_continue_url "http://distribution.virk.dk/_search/scroll"
  @scroll_keepalive "5m"
  @page_size 200
  @company_batch 500
  @report_batch 500

  # 7.46 DKK/EUR ERM II central rate. DKK is pegged within ±2.25% band
  # (in practice ±0.5%) so a constant is fine for revenue-band bucketing.
  # Refresh annually or whenever the peg breaks.
  @dkk_to_eur 0.134

  def run(opts \\ []) do
    max_years =
      Keyword.get(opts, :max_years) ||
        Application.get_env(:colt, :ingest_max_years, 3)

    max_filings =
      Keyword.get(opts, :max_filings) ||
        Application.get_env(:colt, :cvr_dk_max_filings)

    with {:ok, dates} <- target_year_range(max_years),
         {:ok, count} <- ingest_range(dates, max_filings) do
      {:ok, %{processed: count, years: dates, max_filings: max_filings}}
    end
  end

  # ---- target fiscal-year window ----

  # Returns the [from_date, to_date) ISO strings for the scroll's
  # `regnskab.regnskabsperiode.slutDato` range filter.
  #
  # Danish corporates have 5 months after FY end to file (Selskabsloven
  # §138). So in May 2026, last-year (FY2025) filings are still streaming
  # in and the *most recently complete* filing window is FY2024. We bound
  # the upper edge at `today - 5 months` so the scroll always hits a
  # populated set; otherwise we waste round-trips on a near-empty current
  # year and the verification slice has nothing to chew on.
  defp target_year_range(max_years) do
    today = Date.utc_today()
    cutoff = Date.add(today, -150)
    to_year = cutoff.year
    from_year = to_year - max_years + 1
    {:ok, %{from: "#{from_year}-01-01", to: "#{to_year + 1}-01-01"}}
  end

  # ---- scroll → company + report ingest ----

  defp ingest_range(%{from: from, to: to}, max_filings) do
    Logger.info(
      "CVR scroll: regnskab slutDato ∈ [#{from}, #{to})" <>
        if(max_filings, do: " (cap=#{max_filings})", else: "")
    )

    hits =
      scroll_stream(from, to)
      |> maybe_take(max_filings)
      |> Stream.filter(&Sample.included?(&1.registry_code))
      |> Progress.tick("CVR filings scrolled")

    parsed =
      hits
      |> Stream.map(&fetch_and_parse/1)
      |> Stream.reject(&is_nil/1)

    # Two parallel sinks fed off the same stream: companies first
    # (so the report FK has something to point at), then reports.
    # We can't physically fork a Stream without re-running it, so we
    # interleave inside one reduce: per @company_batch entries we
    # flush companies + queued reports together. The chunking matches
    # the playbook's "smallest unit of work" principle — one company
    # insert + one report insert per micro-batch keeps memory bounded.
    {written, _state} =
      parsed
      |> Stream.chunk_every(@company_batch)
      |> Enum.reduce({0, nil}, fn chunk, {n, _} ->
        upsert_companies(chunk)
        by_code = resolve_company_ids(chunk)
        inserted = upsert_reports(chunk, by_code)
        {n + inserted, nil}
      end)

    Progress.done("CVR annual reports upserted", written)
    {:ok, written}
  end

  defp maybe_take(stream, nil), do: stream
  defp maybe_take(stream, n) when is_integer(n), do: Stream.take(stream, n)

  # ---- Elasticsearch scroll iterator ----

  # Emits one map per filing:
  #   %{registry_code: "10204534", year: 2023, xml_url: "...xml"}
  defp scroll_stream(from, to) do
    Stream.resource(
      fn -> start_scroll(from, to) end,
      &advance_scroll/1,
      &finish_scroll/1
    )
  end

  defp start_scroll(from, to) do
    body = %{
      size: @page_size,
      sort: [%{offentliggoerelsesTidspunkt: "asc"}],
      query: %{
        bool: %{
          must: [
            %{term: %{offentliggoerelsestype: "regnskab"}},
            %{range: %{"regnskab.regnskabsperiode.slutDato": %{gte: from, lt: to}}}
          ]
        }
      }
    }

    url = "#{@scroll_url}?scroll=#{@scroll_keepalive}"

    case Req.post(url, json: body, retry: false, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: resp}} ->
        items = extract_hits(resp)
        Logger.info("    CVR scroll: page=1 hits=#{length(items)}")
        %{scroll_id: resp["_scroll_id"], queue: items, done?: items == []}

      other ->
        raise "CVR scroll init failed: #{inspect(other)}"
    end
  end

  defp advance_scroll(%{done?: true} = state), do: {:halt, state}

  defp advance_scroll(%{queue: [h | t]} = state) do
    {[h], %{state | queue: t}}
  end

  defp advance_scroll(%{queue: [], scroll_id: sid} = state) do
    body = %{scroll: @scroll_keepalive, scroll_id: sid}

    case Req.post(@scroll_continue_url,
           json: body,
           retry: :transient,
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: resp}} ->
        items = extract_hits(resp)
        next_sid = resp["_scroll_id"] || sid

        if items == [] do
          {:halt, %{state | scroll_id: next_sid, done?: true}}
        else
          [h | t] = items
          {[h], %{state | scroll_id: next_sid, queue: t}}
        end

      other ->
        Logger.warning("CVR scroll continue failed: #{inspect(other)}")
        {:halt, state}
    end
  end

  defp finish_scroll(%{scroll_id: nil}), do: :ok

  defp finish_scroll(%{scroll_id: sid}) do
    _ =
      Req.delete(@scroll_continue_url,
        json: %{scroll_id: sid},
        retry: false,
        receive_timeout: 10_000
      )

    :ok
  end

  defp extract_hits(resp) do
    resp
    |> get_in(["hits", "hits"])
    |> List.wrap()
    |> Enum.flat_map(&hit_to_filing/1)
  end

  defp hit_to_filing(%{"_source" => src}) do
    cvr = src["cvrNummer"]

    case src do
      %{"regnskab" => %{"regnskabsperiode" => %{"slutDato" => slut}}} ->
        case pick_xbrl_url(src["dokumenter"]) do
          nil -> []
          url -> [%{registry_code: format_cvr(cvr), year: year_of(slut), xml_url: url}]
        end

      _ ->
        []
    end
  end

  defp hit_to_filing(_), do: []

  defp pick_xbrl_url(docs) when is_list(docs) do
    Enum.find_value(docs, fn doc ->
      cond do
        doc["dokumentMimeType"] == "application/xml" and
            doc["dokumentType"] in ["AARSRAPPORT", "AARSRAPPORT_ESEF"] ->
          doc["dokumentUrl"]

        true ->
          nil
      end
    end)
  end

  defp pick_xbrl_url(_), do: nil

  defp format_cvr(n) when is_integer(n) do
    # CVR is 8 digits, left-pad small numbers
    n
    |> Integer.to_string()
    |> String.pad_leading(8, "0")
  end

  defp format_cvr(n) when is_binary(n), do: n

  defp year_of(<<y::binary-size(4), _::binary>>), do: String.to_integer(y)
  defp year_of(_), do: nil

  # ---- per-filing fetch + XBRL parse ----

  defp fetch_and_parse(%{xml_url: url, registry_code: code, year: year}) do
    case Req.get(url,
           retry: :transient,
           receive_timeout: 60_000,
           decode_body: false,
           raw: true,
           connect_options: [timeout: 15_000]
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case decompress(body) do
          {:ok, xml} -> Map.put(parse_xbrl(xml), :registry_code, code) |> Map.put(:year, year)
          :error -> nil
        end

      _ ->
        nil
    end
  rescue
    e ->
      Logger.warning("CVR XBRL fetch crashed for #{code}/#{year}: #{Exception.message(e)}")
      nil
  end

  defp decompress(body) do
    # `regnskaber.virk.dk` serves XBRL as `Content-Encoding: gzip` with
    # `Content-Type: text/xml`. Req with `raw: true` returns the bytes
    # untransformed so we gunzip ourselves. Some older filings are
    # already plain XML — try gunzip, fall back to raw on error.
    try do
      {:ok, :zlib.gunzip(body)}
    rescue
      _ ->
        if String.starts_with?(body, "<?xml") or String.contains?(body, "<xbrl") do
          {:ok, body}
        else
          :error
        end
    end
  end

  # Namespace-agnostic regex parser. Three taxonomies coexist (old
  # `EOGS80000:`, current `fsa:`, ESEF `ifrs-full:`), all with the same
  # local field names. Stripping the namespace prefix keeps the parser
  # working across all three.
  @name_re ~r/<[A-Za-z0-9]+:NameOfReportingEntity[^>]*>([^<]+)</
  @city_re ~r/<[A-Za-z0-9]+:AddressOfReportingEntity(?:DistrictName|PostcodeAndTown)[^>]*>([^<]+)</
  @postcode_re ~r/<[A-Za-z0-9]+:AddressOfReportingEntityPostCodeIdentifier[^>]*>([^<]+)</
  @revenue_re ~r/<[A-Za-z0-9\-]+:Revenue[^>]*>([0-9.\-]+)</
  @employees_re ~r/<[A-Za-z0-9]+:AverageNumberOfEmployees[^>]*>([0-9.\-]+)</

  @doc """
  Parse one XBRL XML document. Returns `%{name, region, revenue_dkk,
  employees}` with nils for missing fields. Public for unit/bench
  introspection — the ingest never calls this from outside.
  """
  def parse_xbrl(xml) when is_binary(xml) do
    %{
      name: capture(@name_re, xml) |> safe_copy(),
      region: pick_region(xml),
      revenue_dkk: capture(@revenue_re, xml) |> parse_decimal(),
      employees: capture(@employees_re, xml) |> parse_employee_count()
    }
  end

  defp capture(re, xml) do
    case Regex.run(re, xml, capture: :all_but_first) do
      [val] -> String.trim(val)
      _ -> nil
    end
  end

  defp pick_region(xml) do
    # Prefer the city; fall back to the combined "postcode-and-town"
    # field on older filings; fall back to postcode-only as last resort.
    city = capture(@city_re, xml) |> safe_copy()
    if city && city != "", do: city, else: capture(@postcode_re, xml) |> safe_copy()
  end

  defp safe_copy(nil), do: nil
  defp safe_copy(s) when is_binary(s), do: :binary.copy(s)

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(s) do
    case Decimal.parse(s) do
      {dec, _} -> dec
      :error -> nil
    end
  end

  defp parse_employee_count(nil), do: nil
  defp parse_employee_count(""), do: nil

  defp parse_employee_count(s) do
    case Float.parse(s) do
      {f, _} -> trunc(f)
      :error -> nil
    end
  end

  defp dkk_to_eur(nil), do: nil

  defp dkk_to_eur(%Decimal{} = d) do
    d
    |> Decimal.mult(Decimal.from_float(@dkk_to_eur))
    |> Decimal.round(0)
  end

  # ---- company upsert (Ash code interface — non-hot path) ----

  defp upsert_companies(parsed_rows) do
    rows =
      parsed_rows
      |> Enum.reject(&(is_nil(&1.name) or &1.name == ""))
      |> Enum.uniq_by(& &1.registry_code)
      |> Enum.map(fn p ->
        %{
          registry_code: p.registry_code,
          market: :dk,
          name: p.name,
          region: p.region,
          status: :registered
        }
      end)

    if rows == [] do
      :ok
    else
      Ash.bulk_create!(rows, Company, :upsert_basic,
        return_errors?: true,
        stop_on_error?: true
      )

      :ok
    end
  end

  # Resolve {registry_code → id} for the codes in this chunk via the
  # resource code interface (no Ash.Query / Ecto leakage outside the
  # resource).
  defp resolve_company_ids(parsed_rows) do
    codes =
      parsed_rows
      |> Enum.map(& &1.registry_code)
      |> Enum.uniq()

    case codes do
      [] ->
        %{}

      _ ->
        Company.ids_by_codes!(:dk, codes)
        |> Map.new(&{&1.registry_code, &1.id})
    end
  end

  # ---- annual_report upsert (raw SQL hot path) ----

  defp upsert_reports(parsed_rows, by_code) do
    rows =
      parsed_rows
      |> Enum.flat_map(fn p ->
        revenue_eur = dkk_to_eur(p.revenue_dkk)

        cond do
          # Drop rows we can't link to a company.
          is_nil(Map.get(by_code, p.registry_code)) ->
            []

          is_nil(p.year) ->
            []

          # Drop rows with no usable financial signal — both nil means
          # the filing was identity-only (rare; usually a corrupt XBRL
          # or a non-AARSRAPPORT document type that slipped through).
          is_nil(revenue_eur) and is_nil(p.employees) ->
            []

          true ->
            [
              %{
                company_id: Map.fetch!(by_code, p.registry_code),
                year: p.year,
                revenue_eur: revenue_eur,
                employees: p.employees,
                source: :cvr
              }
            ]
        end
      end)
      # An amended filing for the same year produces two ES hits; the
      # raw insert chokes on duplicate (company_id, year) inside one
      # statement, so dedupe.
      |> Enum.uniq_by(&{&1.company_id, &1.year})

    chunks = Enum.chunk_every(rows, @report_batch)

    Enum.reduce(chunks, 0, fn chunk, acc ->
      acc + bulk_insert_ignore(chunk)
    end)
  end

  # Raw multi-row INSERT … ON CONFLICT DO NOTHING. Same shape as
  # `Colt.Services.Ingest.Ee.Rik.AnnualReports.bulk_insert_ignore/1`.
  # See `docs/large-csv-ingest.md` for why this bypasses Ash.
  defp bulk_insert_ignore([]), do: 0

  defp bulk_insert_ignore(rows) do
    count = length(rows)
    now = DateTime.utc_now()

    ids = Enum.map(rows, fn _ -> Ecto.UUID.bingenerate() end)
    company_ids = Enum.map(rows, &Ecto.UUID.dump!(&1.company_id))
    years = Enum.map(rows, & &1.year)
    revenues = Enum.map(rows, & &1.revenue_eur)
    employees = Enum.map(rows, & &1.employees)
    sources = Enum.map(rows, &Atom.to_string(&1.source))
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
end
