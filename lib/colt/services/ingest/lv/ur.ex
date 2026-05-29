defmodule Colt.Services.Ingest.Lv.Ur do
  @moduledoc """
  Orchestrates a full Uzņēmumu reģistrs (LV) open-data ingest.

  Stages, each its own module under `Colt.Services.Ingest.Lv.Ur.*`:

  1. `Download` — fetches `register.csv`, `financial_statements.csv` and
     `income_statements.csv` from `data.gov.lv` into the cache directory.
     All three are plain CC0-1.0 CSVs; no auth, no zips.
  2. `CompaniesImport` — streams `register.csv` and upserts every Latvian
     entity through `Company.upsert_basic`. Mirrors the EE/RIK shape.
  3. `AnnualReports` — joins `financial_statements.csv` (header with
     `regcode`, year, employees) to `income_statements.csv` (net_turnover
     keyed by `statement_id`) and bulk-inserts last-3-years rows via raw
     SQL `INSERT … ON CONFLICT DO NOTHING`.
  4. `GrowthRollup` — reuses `Ee.Rik.GrowthRollup.run/0`. The SQL is
     market-agnostic; it projects every company's two latest reports
     onto `revenue_latest`, `employees_latest`, `revenue_growth_bucket`.

  See `docs/countries/lv.md` for source URLs, coverage estimate, the
  NACE-code gap, and the verbatim Oban cron line.
  """

  require Logger

  alias Colt.Services.Ingest.Ee.Rik.GrowthRollup
  alias Colt.Services.Ingest.Lv.Ur.{AnnualReports, CompaniesImport, Download}

  @stages 4

  def run(opts \\ []) do
    started = System.monotonic_time(:millisecond)
    from = Keyword.get(opts, :from, 1)

    with {:ok, downloads} <-
           maybe_stage(1, from, "Downloading UR (LV) dumps", &Download.run/0),
         {:ok, companies} <-
           maybe_stage(2, from, "Importing companies (register.csv)", &CompaniesImport.run/0),
         {:ok, reports} <-
           maybe_stage(3, from, "Importing annual reports (UR financials)", &AnnualReports.run/0),
         {:ok, growth} <-
           maybe_stage(4, from, "Recomputing growth rollup", &GrowthRollup.run/0) do
      cleanup_cache()
      Logger.info("UR (LV) ingest finished in #{seconds(started)}s")

      {:ok,
       %{
         downloads: downloads,
         companies: companies,
         reports: reports,
         growth: growth
       }}
    end
  end

  # Wipes the UR cache once the full ingest has succeeded. Same rationale
  # as Ee.Rik: the three CSVs together are ~450 MB and re-downloading from
  # data.gov.lv is cheap (HTTP HEAD-able, daily-fresh).
  defp cleanup_cache do
    dir = Application.fetch_env!(:colt, :ur_lv_cache_dir)
    abs_dir = if Path.type(dir) == :absolute, do: dir, else: Application.app_dir(:colt, dir)

    case File.ls(abs_dir) do
      {:ok, names} ->
        Enum.each(names, fn name -> _ = File.rm(Path.join(abs_dir, name)) end)
        Logger.info("UR cache cleared: #{abs_dir} (#{length(names)} files)")

      {:error, reason} ->
        Logger.warning("UR cache cleanup skipped: #{inspect(reason)}")
    end
  end

  defp maybe_stage(n, from, _label, _fun) when n < from do
    Logger.info("[#{n}/#{@stages}] skipped")
    {:ok, :skipped}
  end

  defp maybe_stage(n, _from, label, fun) do
    Logger.info("[#{n}/#{@stages}] #{label}…")
    started = System.monotonic_time(:millisecond)
    result = fun.()
    Logger.info("[#{n}/#{@stages}] done in #{seconds(started)}s")
    result
  end

  defp seconds(started_ms) do
    ((System.monotonic_time(:millisecond) - started_ms) / 1000)
    |> Float.round(1)
  end
end
