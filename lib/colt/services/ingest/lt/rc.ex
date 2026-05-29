defmodule Colt.Services.Ingest.Lt.Rc do
  @moduledoc """
  Orchestrates the Registrų centras (Lithuania) ingest. Identity + revenue
  only — headcount comes from Sodra (`Colt.Services.Ingest.Lt.Sodra`).

  See `docs/countries/lt.md` for sources, field meanings, and the
  rationale for keeping RC and Sodra as separate top-level services.

  Stages (each under `Colt.Services.Ingest.Lt.Rc.*`):

  1. `Download` — pulls JAR_IREGISTRUOTI.csv plus per-year
     JAR_FA_RODIKLIAI_PLNA_YYYY.csv files into the cache dir.
  2. `CompaniesImport` — upserts every Lithuanian legal entity from JAR.
  3. `AnnualReports` — upserts profit/loss rows with `source: :rc`,
     `revenue_eur` from `pardavimo_pajamos`, `employees: nil`.
  4. `GrowthRollup` — projects the latest two reports per company onto
     `revenue_latest` / `employees_latest` / `revenue_growth_bucket`.
     Shared with RIK because the rollup is market-agnostic.

  `run(from: n)` resumes from stage `n`; same shape as RIK and PRH.
  """

  require Logger

  alias Colt.Services.Ingest.Ee.Rik.GrowthRollup
  alias Colt.Services.Ingest.Lt.Rc.{AnnualReports, CompaniesImport, Download}

  @stages 4

  def run(opts \\ []) do
    started = System.monotonic_time(:millisecond)
    from = Keyword.get(opts, :from, 1)

    with {:ok, downloads} <-
           maybe_stage(1, from, "Downloading RC LT dumps", &Download.run/0),
         {:ok, companies} <-
           maybe_stage(2, from, "Importing companies (JAR_IREGISTRUOTI)", &CompaniesImport.run/0),
         {:ok, reports} <-
           maybe_stage(3, from, "Importing annual reports (pelno)", &AnnualReports.run/0),
         {:ok, growth} <-
           maybe_stage(4, from, "Recomputing growth rollup", &GrowthRollup.run/0) do
      cleanup_cache()
      Logger.info("RC LT ingest finished in #{seconds(started)}s")

      {:ok,
       %{
         downloads: downloads,
         companies: companies,
         reports: reports,
         growth: growth
       }}
    end
  end

  defp cleanup_cache do
    dir = Application.fetch_env!(:colt, :rc_lt_cache_dir)
    abs_dir = if Path.type(dir) == :absolute, do: dir, else: Application.app_dir(:colt, dir)

    case File.ls(abs_dir) do
      {:ok, names} ->
        Enum.each(names, fn name -> _ = File.rm(Path.join(abs_dir, name)) end)
        Logger.info("RC LT cache cleared: #{abs_dir} (#{length(names)} files)")

      {:error, reason} ->
        Logger.warning("RC LT cache cleanup skipped: #{inspect(reason)}")
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
    ((System.monotonic_time(:millisecond) - started_ms) / 1000) |> Float.round(1)
  end
end
