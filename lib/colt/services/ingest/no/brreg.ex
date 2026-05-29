defmodule Colt.Services.Ingest.No.Brreg do
  @moduledoc """
  Orchestrates a full BRREG (Brønnøysundregistrene) ingest for the Norwegian
  market. See `docs/countries/no.md` for sources, volumes, coverage caveats,
  and the NOK→EUR FX constant.

  Stages, each its own module under `Colt.Services.Ingest.No.Brreg.*`:

  1. `Download` — fetches the gzipped `enheter_alle.csv.gz` into the cache
     directory. No unzip step — stage 2 streams gzip directly.
  2. `CompaniesImport` — NimbleCSV-parses the dump and upserts every
     Norwegian entity via `Company.upsert_full` (identity, industry, region,
     status, optional website all from one CSV row).
  3. `AnnualReports` — `Task.async_stream` GETs
     `data.brreg.no/regnskapsregisteret/regnskap/{orgnr}` for every AS with a
     filed annual account, converts NOK→EUR via the documented constant rate,
     and inserts rows with raw-SQL `unnest(…) ON CONFLICT DO NOTHING`.
     Employees come from the enhetsregister CSV's `antallAnsatte` column
     (the regnskap API does not carry an employee field) and are stamped
     onto each company's most recent fiscal year only.
  4. `GrowthRollup` — same SQL pass as the EE pipeline; projects the two
     most recent reports onto `companies.{revenue_latest, employees_latest,
     revenue_growth_bucket}`.

  Run with `limit: N` to bound the regnskap stage to the first N orgnrs
  for verification (companies stage is unaffected — it just streams the
  whole dump).
  """

  require Logger

  alias Colt.Services.Ingest.No.Brreg.{
    AnnualReports,
    CompaniesImport,
    Download,
    GrowthRollup
  }

  @stages 4

  def run(opts \\ []) do
    started = System.monotonic_time(:millisecond)
    from = Keyword.get(opts, :from, 1)
    limit = Keyword.get(opts, :limit)

    with {:ok, downloads} <-
           maybe_stage(1, from, "Downloading BRREG enheter dump", &Download.run/0),
         {:ok, companies} <-
           maybe_stage(2, from, "Importing companies (enheter CSV)", &CompaniesImport.run/0),
         {:ok, reports} <-
           maybe_stage(
             3,
             from,
             "Importing annual reports (regnskap API)",
             fn -> AnnualReports.run(limit: limit) end
           ),
         {:ok, growth} <-
           maybe_stage(4, from, "Recomputing growth rollup", &GrowthRollup.run/0) do
      cleanup_cache()
      Logger.info("BRREG ingest finished in #{seconds(started)}s")

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
    dir = Application.fetch_env!(:colt, :brreg_no_cache_dir)
    abs_dir = if Path.type(dir) == :absolute, do: dir, else: Application.app_dir(:colt, dir)

    case File.ls(abs_dir) do
      {:ok, names} ->
        Enum.each(names, fn name -> _ = File.rm(Path.join(abs_dir, name)) end)
        Logger.info("BRREG cache cleared: #{abs_dir} (#{length(names)} files)")

      {:error, reason} ->
        Logger.warning("BRREG cache cleanup skipped: #{inspect(reason)}")
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
