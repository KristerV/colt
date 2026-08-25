defmodule Colt.Services.Admin.IndustryGrowth do
  @moduledoc """
  Year-over-year revenue growth per NACE industry, for `/admin/industries`.

  Answers "which market is expanding fastest" off `annual_reports`, rolled up
  the same four-level tree the campaign filters use (section → division →
  group → 4-digit class).

  ## The cohort

  A company counts for an industry only when **all** of these hold:

    * it has an annual report in *both* compared years, with a revenue figure
      in each — so growth is like-for-like and new entrants / dead companies
      can't move the number;
    * its latest-year revenue is at least €500k, keeping
      micro-companies out (a €40k shop tripling is noise, not a market);
    * its base-year revenue is above zero — a ratio off a zero base is not a
      number we can plot.

  Companies are attributed to an industry by `LEFT(industry_code, 4)`, the NACE
  class: EMTAK codes are 5 digits and the 5th is a national subclass that
  doesn't change the wording. Codes are normalised to Rev. 2.1 at import, so
  only one vocabulary reaches this module.

  ## The two growth numbers

  Every node carries both, because they answer different questions:

    * `total_ratio` — summed revenue, latest ÷ base. Where the money is. One
      large company can carry a whole industry here.
    * `median_ratio` — the median of each company's own ratio. How the typical
      company in that industry did, immune to a single giant.

  When they disagree sharply, that itself is the finding: a consolidating
  market has total up and median flat.

  Nodes thinner than 10 companies keep their row but report no
  growth (`thin?: true`) — three companies can produce a 30× that means
  nothing. Their revenue still rolls up into their parents.
  """

  alias Colt.Filters.IndustryLabels

  # Latest-year revenue floor for a company to be counted, in EUR.
  @min_revenue_eur 500_000

  # Below this many companies a node reports no growth figure.
  @min_companies 10

  # Division → section letter, resolved once at compile time and passed to
  # Postgres as a pair of arrays so the rollup happens in one query.
  @division_sections (for {letter, _title} <- IndustryLabels.sections(),
                          {division, _label} <- IndustryLabels.divisions_for_section(letter),
                          do: {division, letter})

  def min_revenue_eur, do: @min_revenue_eur
  def min_companies, do: @min_companies

  @doc """
  The pair of years the page compares: last calendar year against the one
  before it. Deliberately not "the newest year in the table" — a year that is
  only half-filed would read as an industry-wide collapse.
  """
  def year_pair do
    latest = Date.utc_today().year - 1
    {latest - 1, latest}
  end

  @doc """
  Growth for every industry node in `market`, plus the market-wide totals.

  Returns

      %{
        base_year: 2024,
        latest_year: 2025,
        nodes: %{"C" => metrics, "62" => metrics, ...},
        market_total: metrics | nil,
        years_available: [{year, companies_with_revenue}]
      }

  where each `metrics` is

      %{companies: 34, base_total: %Decimal{}, latest_total: %Decimal{},
        change: %Decimal{}, total_ratio: 1.18, median_ratio: 1.04,
        share: 0.07, thin?: false}

  `total_ratio` / `median_ratio` / `share` are nil on a thin node.
  `market_total` is nil when no company in the market clears the cohort rules.
  """
  def load(market) when is_atom(market) do
    {base_year, latest_year} = year_pair()
    rows = query_rows(market, base_year, latest_year)

    {market_rows, node_rows} = Enum.split_with(rows, &(&1.node == :market))
    market_total = market_rows |> List.first() |> metrics(nil)

    %{
      base_year: base_year,
      latest_year: latest_year,
      market_total: market_total,
      nodes: Map.new(node_rows, &{&1.node, metrics(&1, market_total)}),
      years_available: years_available(market)
    }
  end

  defp metrics(nil, _market), do: nil

  defp metrics(row, market) do
    thin? = row.companies < @min_companies

    %{
      companies: row.companies,
      base_total: row.base_total,
      latest_total: row.latest_total,
      change: Decimal.sub(row.latest_total, row.base_total),
      total_ratio: if(thin?, do: nil, else: ratio(row.latest_total, row.base_total)),
      median_ratio: if(thin?, do: nil, else: row.median_ratio),
      share: share(row.latest_total, market),
      thin?: thin?
    }
  end

  defp ratio(latest, base) do
    if Decimal.compare(base, 0) == :gt do
      latest |> Decimal.div(base) |> Decimal.to_float()
    end
  end

  # A node's cut of the market's latest-year revenue. Thin nodes still get one:
  # it's a measured size, not an inferred growth rate.
  defp share(_latest, nil), do: nil
  defp share(latest, %{latest_total: total}), do: ratio(latest, total)

  # One pass over the cohort, grouped at all four levels at once plus a grand
  # total. GROUPING SETS keeps the medians exact — a median can't be rolled up
  # from its children the way a sum can, so every level has to see the raw
  # per-company ratios.
  defp query_rows(market, base_year, latest_year) do
    {divisions, letters} = Enum.unzip(@division_sections)

    sql = """
    WITH sect(div2, letter) AS (
      SELECT * FROM unnest($4::text[], $5::text[])
    ),
    pairs AS (
      SELECT
        s.letter                                            AS letter,
        LEFT(c.industry_code, 2)                            AS div2,
        LEFT(c.industry_code, 3)                            AS grp3,
        LEFT(c.industry_code, 4)                            AS class4,
        base.revenue_eur                                    AS base_total,
        latest.revenue_eur                                  AS latest_total,
        (latest.revenue_eur / base.revenue_eur)::float8     AS growth
      FROM companies c
      JOIN annual_reports base
        ON base.company_id = c.id AND base.year = $2
      JOIN annual_reports latest
        ON latest.company_id = c.id AND latest.year = $3
      JOIN sect s ON s.div2 = LEFT(c.industry_code, 2)
      WHERE c.market = $1
        AND c.industry_code IS NOT NULL
        AND length(c.industry_code) >= 4
        AND base.revenue_eur > 0
        AND latest.revenue_eur >= $6
    )
    SELECT
      GROUPING(letter) AS g_letter,
      GROUPING(div2)   AS g_div,
      GROUPING(grp3)   AS g_grp,
      GROUPING(class4) AS g_class,
      letter, div2, grp3, class4,
      count(*)         AS companies,
      sum(base_total)  AS base_total,
      sum(latest_total) AS latest_total,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY growth) AS median_ratio
    FROM pairs
    GROUP BY GROUPING SETS (
      (),
      (letter),
      (letter, div2),
      (letter, div2, grp3),
      (letter, div2, grp3, class4)
    )
    """

    params = [
      to_string(market),
      base_year,
      latest_year,
      divisions,
      letters,
      Decimal.new(@min_revenue_eur)
    ]

    %{rows: rows} = Colt.Repo.query!(sql, params)

    rows
    |> Enum.map(fn [g_letter, g_div, g_grp, g_class | rest] ->
      [letter, div2, grp3, class4, companies, base_total, latest_total, median_ratio] = rest

      %{
        node: node_id(g_letter, g_div, g_grp, g_class, letter, div2, grp3, class4),
        companies: companies,
        base_total: base_total,
        latest_total: latest_total,
        median_ratio: median_ratio
      }
    end)
    # An empty cohort still yields one grand-total row, with a zero count and
    # null sums. Nothing downstream can do arithmetic on that, so drop it here
    # and let the page render its "no data" state.
    |> Enum.reject(&(&1.companies == 0))
  end

  # GROUPING() returns 1 for a column rolled up in this grouping set, so the
  # first 0 walking down the tree names the level the row belongs to.
  defp node_id(1, _, _, _, _, _, _, _), do: :market
  defp node_id(0, 1, _, _, letter, _, _, _), do: letter
  defp node_id(0, 0, 1, _, _, div2, _, _), do: div2
  defp node_id(0, 0, 0, 1, _, _, grp3, _), do: grp3
  defp node_id(0, 0, 0, 0, _, _, _, class4), do: class4

  @doc """
  Which years this market actually has revenue filings for, newest first —
  what the page shows when the compared pair comes back empty.
  """
  def years_available(market, limit \\ 6) when is_atom(market) do
    sql = """
    SELECT a.year, count(*)
    FROM annual_reports a
    JOIN companies c ON c.id = a.company_id
    WHERE c.market = $1 AND a.revenue_eur IS NOT NULL
    GROUP BY a.year
    ORDER BY a.year DESC
    LIMIT $2
    """

    %{rows: rows} = Colt.Repo.query!(sql, [to_string(market), limit])

    Enum.map(rows, fn [year, count] -> {year, count} end)
  end
end
