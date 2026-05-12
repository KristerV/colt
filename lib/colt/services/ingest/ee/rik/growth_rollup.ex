defmodule Colt.Services.Ingest.Ee.Rik.GrowthRollup do
  @moduledoc """
  Single-pass UPDATE that projects each company's two most recent annual
  reports onto `companies.{revenue_latest, employees_latest,
  revenue_growth_bucket}`. Buckets per spec §3.1.

  Split from `AnnualReports` so a partial crash during report inserts (or a
  DB drop between insert + rollup) can be repaired with
  `Rik.run(from: 5)` without re-importing the 400k+ report rows.
  """

  alias Colt.Services.Ingest.Progress

  def run do
    with {:ok, n} <- recompute() do
      {:ok, %{updated: n}}
    end
  end

  defp recompute do
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
