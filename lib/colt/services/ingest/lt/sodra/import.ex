defmodule Colt.Services.Ingest.Lt.Sodra.Import do
  @moduledoc """
  Imports harvested Sodra rows (`Harvest.run/1`) into the DB. One Sodra row per
  company carries both signals, so this writes to two places:

    * **employees** → `annual_reports.employees` for `(company_id, fiscal_year)` with
      `source: :sodra` (headcount always wins; `source` stays `:rc` when RC revenue
      already exists for that year). `GrowthRollup` later projects `employees_latest`.
    * **NACE** → `companies.industry_code`, the EVRK code stored as bare digits
      (e.g. `"702000"`). The `:filtered` action matches on `LEFT(industry_code, 4)`.

  Rows are matched to companies by `(registry_code, market: :lt)`. Rows whose company
  is not in our table (not yet ingested from RC) are skipped.

  Raw SQL bulk upserts, per `docs/large-csv-ingest.md` — Ash changesets are 100–1000×
  slower at this row count.
  """

  require Logger

  alias Colt.Repo
  alias Colt.Resources.Company

  @batch 5_000

  def run(rows) when is_list(rows) do
    with {:ok, by_code} <- index_companies(),
         resolved <- resolve(rows, by_code),
         {:ok, employees} <- upsert_employees(resolved),
         {:ok, industry} <- upsert_industry(resolved) do
      Logger.info("Sodra import: #{employees} headcounts, #{industry} NACE codes")
      {:ok, %{matched: length(resolved), employees: employees, industry: industry}}
    end
  end

  # registry_code => company_id for all LT companies.
  defp index_companies do
    companies =
      Company
      |> Ash.Query.for_read(:list_by_market, %{market: :lt})
      |> Ash.Query.select([:id, :registry_code])
      |> Ash.read!()

    {:ok, Map.new(companies, &{&1.registry_code, &1.id})}
  end

  # Keep only rows whose company we know; dedupe by company keeping the latest year.
  defp resolve(rows, by_code) do
    rows
    |> Enum.reduce(%{}, fn row, acc ->
      case Map.get(by_code, row.registry_code) do
        nil ->
          acc

        id ->
          candidate = Map.put(row, :company_id, id)

          Map.update(acc, id, candidate, fn existing ->
            if (row.year || 0) >= (existing.year || 0), do: candidate, else: existing
          end)
      end
    end)
    |> Map.values()
  end

  # --- employees -> annual_reports ---------------------------------------------

  defp upsert_employees(resolved) do
    rows = Enum.filter(resolved, &(&1.employees && &1.year))

    count =
      rows
      |> Enum.chunk_every(@batch)
      |> Enum.reduce(0, fn chunk, acc -> acc + bulk_upsert_employees(chunk) end)

    {:ok, count}
  end

  defp bulk_upsert_employees([]), do: 0

  defp bulk_upsert_employees(rows) do
    now = DateTime.utc_now()
    n = length(rows)

    ids = Enum.map(rows, fn _ -> Ecto.UUID.bingenerate() end)
    company_ids = Enum.map(rows, &Ecto.UUID.dump!(&1.company_id))
    years = Enum.map(rows, & &1.year)
    revenues = List.duplicate(nil, n)
    employees = Enum.map(rows, & &1.employees)
    sources = List.duplicate("sodra", n)
    stamps = List.duplicate(now, n)

    sql = """
    INSERT INTO annual_reports
      (id, company_id, year, revenue_eur, employees, source, inserted_at, updated_at)
    SELECT * FROM unnest(
      $1::uuid[], $2::uuid[], $3::int[], $4::numeric[], $5::int[], $6::text[],
      $7::timestamptz[], $8::timestamptz[]
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

    Ecto.Adapters.SQL.query!(Repo, sql, [
      ids,
      company_ids,
      years,
      revenues,
      employees,
      sources,
      stamps,
      stamps
    ])

    n
  end

  # --- NACE -> companies.industry_code -----------------------------------------

  defp upsert_industry(resolved) do
    rows = Enum.filter(resolved, & &1.evrk)

    count =
      rows
      |> Enum.chunk_every(@batch)
      |> Enum.reduce(0, fn chunk, acc -> acc + bulk_update_industry(chunk) end)

    {:ok, count}
  end

  defp bulk_update_industry([]), do: 0

  defp bulk_update_industry(rows) do
    company_ids = Enum.map(rows, &Ecto.UUID.dump!(&1.company_id))
    codes = Enum.map(rows, & &1.evrk)

    sql = """
    UPDATE companies c
    SET industry_code = v.evrk, updated_at = now()
    FROM unnest($1::uuid[], $2::text[]) AS v(id, evrk)
    WHERE c.id = v.id AND c.industry_code IS DISTINCT FROM v.evrk
    """

    %{num_rows: n} = Ecto.Adapters.SQL.query!(Repo, sql, [company_ids, codes])
    n
  end
end
