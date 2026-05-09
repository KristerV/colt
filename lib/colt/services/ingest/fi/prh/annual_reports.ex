defmodule Colt.Services.Ingest.Fi.Prh.AnnualReports do
  @moduledoc """
  Walks the PRH iXBRL Open Data API for the configured fiscal-year ends
  and writes one `Colt.Resources.AnnualReport` per (company, year) with
  revenue + an estimated employee count.

  Per-year flow:
    1. Page `/all_financials?financialDate=YYYY-MM-DD` (100 per page) to
       enumerate every iXBRL filing for that FY end.
    2. For each filing, fetch `/financial?businessId=&financialDate=` and
       parse the XBRL XML for `Liikevaihto` (revenue) and `Palkat ja
       palkkiot` (wage bill). Employee count is estimated as
       `wage_bill / @avg_employee_cost`.
    3. Bulk-upsert. Single connection, sequential — PRH rate-limits
       parallel fetches.

  At the end, `recompute_growth/0` runs the same SQL pass as the EE
  ingest so revenue_latest / employees_latest / growth_bucket are kept
  in sync across all sources.

  Run-shaping:
    * `Application.get_env(:colt, :ingest_max_years, 3)` controls how many
      most-recent FY ends to walk.
    * `Application.get_env(:colt, :prh_fi_max_filings, nil)` caps total
      filings processed per run (set in dev to keep iterations cheap).
  """

  require Logger

  alias Colt.Resources.{AnnualReport, Company}
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @listing_url "https://avoindata.prh.fi/opendata-xbrl-api/v3/all_financials"
  @filing_url "https://avoindata.prh.fi/opendata-xbrl-api/v3/financial"
  @page_size 100
  @batch 200
  # Approximate Finnish full-time employee cost (incl. employer contributions)
  # used to back-estimate headcount from the reported wage bill.
  @avg_employee_cost 50_000

  # MCY dimension members from the OYTP taxonomy. See plan file for
  # full mapping; only the two we need are repeated here.
  @mcy_revenue "fi_MC:x673"
  @mcy_wages "fi_MC:x6"
  @mcy_personnel_total "fi_MC:x5"

  def run do
    with {:ok, dates} <- target_dates(),
         {:ok, count} <- ingest_dates(dates),
         {:ok, recomputed} <- recompute_growth() do
      {:ok, %{processed: count, dates: dates, growth_recomputed: recomputed}}
    end
  end

  # ---- target FY ends ----

  # Finnish accounting law gives companies 6 months after FY end to file the
  # annual report (so calendar-year filings land by June 30 the following
  # year). Until July, the most recently *complete* FY end is two calendar
  # years ago. Walking the still-being-filed year wastes ~all the requests
  # on a near-empty index that rate-limits us.
  defp target_dates do
    max_years = Application.get_env(:colt, :ingest_max_years, 3)
    today = Date.utc_today()
    most_recent_complete = if today.month >= 7, do: today.year - 1, else: today.year - 2

    dates =
      most_recent_complete..(most_recent_complete - max_years + 1)//-1
      |> Enum.map(&"#{&1}-12-31")

    Logger.info("PRH XBRL target dates: #{Enum.join(dates, ", ")}")
    {:ok, dates}
  end

  # ---- per-date ingest ----

  defp ingest_dates(dates) do
    cap = Application.get_env(:colt, :prh_fi_max_filings)

    {total, _remaining} =
      Enum.reduce(dates, {0, cap}, fn date, {acc, cap} ->
        case cap do
          0 ->
            {acc, 0}

          _ ->
            n = ingest_date(date, cap)
            new_cap = if cap, do: max(cap - n, 0), else: nil
            {acc + n, new_cap}
        end
      end)

    {:ok, total}
  end

  defp ingest_date(date, cap) do
    Logger.info("PRH XBRL: walking financialDate=#{date}")

    filings =
      stream_listing_pages(date)
      |> Stream.flat_map(&resolve_companies/1)
      |> Stream.filter(&Sample.included?(&1.business_id))
      |> maybe_take(cap)

    count =
      filings
      |> Progress.tick("PRH filings (#{date})")
      |> Stream.map(&fetch_and_parse(&1, date))
      |> Stream.reject(&is_nil/1)
      |> Stream.map(&build_report(&1, date))
      |> Stream.reject(&is_nil/1)
      |> Stream.chunk_every(@batch)
      |> Enum.reduce(0, fn chunk, n ->
        Ash.bulk_create!(chunk, AnnualReport, :upsert,
          return_errors?: true,
          stop_on_error?: true
        )

        n + length(chunk)
      end)

    Progress.done("PRH annual reports upserted (#{date})", count)
    count
  end

  # Per-page registry_code → id lookup. Keeps memory flat regardless of how
  # many FI companies exist locally — only the ~100 codes from the current
  # listing page are resolved at a time. Filings whose business_id has no
  # matching local company are dropped here.
  defp resolve_companies(filings) do
    codes = filings |> Enum.map(& &1.business_id) |> Enum.uniq()

    by_code =
      Company.ids_by_codes!(:fi, codes)
      |> Map.new(&{&1.registry_code, &1.id})

    filings
    |> Enum.flat_map(fn f ->
      case Map.get(by_code, f.business_id) do
        nil -> []
        id -> [Map.put(f, :company_id, id)]
      end
    end)
  end

  defp maybe_take(stream, nil), do: stream
  defp maybe_take(stream, n) when is_integer(n), do: Stream.take(stream, n)

  # ---- listing pagination ----

  defp stream_listing_pages(date) do
    Stream.unfold(1, fn
      :done ->
        nil

      page ->
        case fetch_listing_page(date, page) do
          {:ok, items, has_more?} ->
            next = if has_more?, do: page + 1, else: :done
            {items, next}

          :error ->
            nil
        end
    end)
  end

  defp fetch_listing_page(date, page) do
    url = "#{@listing_url}?financialDate=#{date}&page=#{page}"

    case Req.get(url, retry: :transient, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: body}} ->
        items =
          body
          |> Map.get("financials", [])
          |> Enum.map(fn f ->
            %{business_id: f["businessId"], financial_date: f["financialDate"]}
          end)

        total = Map.get(body, "totalResults", 0)
        seen = page * @page_size
        {:ok, items, length(items) > 0 and seen < total}

      other ->
        Logger.warning("PRH listing fetch failed page=#{page} date=#{date}: #{inspect(other)}")
        :error
    end
  end

  # ---- single filing fetch + parse ----

  defp fetch_and_parse(%{business_id: bid, company_id: cid}, date) do
    url = "#{@filing_url}?businessId=#{bid}&financialDate=#{date}"

    case Req.get(url, retry: :transient, receive_timeout: 60_000, decode_body: false) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        parsed = parse_xbrl(body, date)
        Map.merge(parsed, %{business_id: bid, company_id: cid})

      _ ->
        nil
    end
  end

  # ---- XBRL extraction (regex-based; XBRL is structurally regular) ----
  # Two passes:
  #   1. Build map context_id → MCY member by walking <context>…</context>.
  #   2. Walk every <fi_met:md103 contextRef="X">VALUE</…> fact, look up
  #      its context's MCY member, keep facts whose member is one of our
  #      target codes (revenue / wages / personnel costs).

  @context_re ~r/<context\b[^>]*\bid="([^"]+)"[^>]*>(.*?)<\/context>/s
  @mcy_re ~r/dimension="fi_dim:MCY"[^>]*>([^<]+)</
  @period_end_re ~r/<(?:instant|endDate)>([\d-]+)<\/(?:instant|endDate)>/
  @fact_re ~r/<fi_met:md103\b[^>]*\bcontextRef="([^"]+)"[^>]*>([\d.\-]+)<\/fi_met:md103>/

  @doc """
  Extract revenue + wage facts from one XBRL filing.

  `target_date` (e.g. "2024-12-31") filters out comparison-period contexts
  so we only keep facts dated to the requested fiscal year end.
  """
  def parse_xbrl(xml, target_date \\ nil) when is_binary(xml) do
    ctx_map =
      Regex.scan(@context_re, xml, capture: :all_but_first)
      |> Enum.reduce(%{}, fn [cid, body], acc ->
        with [member] <- Regex.run(@mcy_re, body, capture: :all_but_first),
             [period_end] <- Regex.run(@period_end_re, body, capture: :all_but_first),
             true <- target_date == nil or period_end == target_date do
          Map.put(acc, cid, member)
        else
          _ -> acc
        end
      end)

    facts =
      Regex.scan(@fact_re, xml, capture: :all_but_first)
      |> Enum.reduce(%{}, fn [cid, val], acc ->
        case Map.get(ctx_map, cid) do
          nil -> acc
          member -> Map.put(acc, member, parse_decimal(val))
        end
      end)

    %{
      revenue: facts[@mcy_revenue] |> abs_decimal(),
      wages: facts[@mcy_wages] |> abs_decimal(),
      personnel_total: facts[@mcy_personnel_total] |> abs_decimal()
    }
  end

  defp abs_decimal(nil), do: nil
  defp abs_decimal(%Decimal{} = d), do: Decimal.abs(d)

  defp build_report(parsed, date) do
    case parsed.revenue do
      nil ->
        nil

      rev ->
        year = String.to_integer(String.slice(date, 0, 4))

        %{
          company_id: parsed.company_id,
          year: year,
          revenue_eur: rev,
          employees: estimate_employees(parsed),
          source: :prh_ixbrl
        }
    end
  end

  # Prefer Palkat ja palkkiot (gross wages). Fall back to Henkilöstökulut
  # divided by 1.25 to back out ~25% employer contributions. Floor at 0.
  defp estimate_employees(%{wages: nil, personnel_total: nil}), do: nil

  defp estimate_employees(%{wages: %Decimal{} = w}) do
    w
    |> Decimal.to_float()
    |> derive_count()
  end

  defp estimate_employees(%{personnel_total: %Decimal{} = pt}) do
    pt
    |> Decimal.to_float()
    |> Kernel./(1.25)
    |> derive_count()
  end

  defp estimate_employees(_), do: nil

  defp derive_count(amount) when amount > 0 do
    amount
    |> Kernel./(@avg_employee_cost)
    |> Float.round()
    |> trunc()
    |> max(0)
  end

  defp derive_count(_), do: nil

  defp parse_decimal(s) do
    case Decimal.parse(s) do
      {dec, _} -> dec
      :error -> nil
    end
  end

  # ---- growth recompute (same SQL as EE; source-agnostic) ----

  defp recompute_growth do
    sql = """
    WITH ranked AS (
      SELECT
        company_id,
        revenue_eur,
        employees,
        year,
        ROW_NUMBER() OVER (PARTITION BY company_id ORDER BY year DESC) AS rn
      FROM annual_reports
    ),
    agg AS (
      SELECT
        company_id,
        MAX(revenue_eur) FILTER (WHERE rn = 1) AS revenue_latest,
        MAX(employees)   FILTER (WHERE rn = 1) AS employees_latest,
        MAX(revenue_eur) FILTER (WHERE rn = 2) AS revenue_prev
      FROM ranked
      GROUP BY company_id
    ),
    growth AS (
      SELECT
        company_id,
        revenue_latest,
        employees_latest,
        CASE
          WHEN revenue_prev IS NULL OR revenue_latest IS NULL THEN NULL
          WHEN revenue_prev <= 0 AND revenue_latest > 0 THEN 'growing_10x'
          WHEN revenue_prev <= 0 THEN 'stagnant'
          WHEN revenue_latest < revenue_prev THEN 'declining'
          WHEN (revenue_latest - revenue_prev) / revenue_prev <= 0.05 THEN 'stagnant'
          WHEN (revenue_latest - revenue_prev) / revenue_prev <= 1.0  THEN 'slow'
          WHEN (revenue_latest - revenue_prev) / revenue_prev <= 9.0  THEN 'growing_2x'
          ELSE 'growing_10x'
        END AS bucket
      FROM agg
    )
    UPDATE companies c
    SET
      revenue_latest = g.revenue_latest,
      employees_latest = g.employees_latest,
      revenue_growth_bucket = g.bucket
    FROM growth g
    WHERE c.id = g.company_id
    """

    {:ok, %{num_rows: n}} = Ecto.Adapters.SQL.query(Colt.Repo, sql, [])
    Progress.done("growth recomputed", n)
    {:ok, n}
  end
end
