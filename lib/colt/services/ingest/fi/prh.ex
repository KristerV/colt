defmodule Colt.Services.Ingest.Fi.Prh do
  @moduledoc """
  Orchestrates a full PRH (Finnish Patent and Registration Office) ingest.

  Stages, each its own service module under `Colt.Services.Ingest.Fi.Prh.*`:

  1. `Download` — fetches the `/all_companies` ZIP and converts it to
     newline-delimited JSON via `jq -c '.[]'`.
  2. `CompaniesImport` — streams the NDJSON, upserting every Finnish
     company through `Company.upsert_full` (identity + industry + website
     in one shot).
  3. `AnnualReports` — walks the iXBRL Open Data API for the configured
     fiscal-year ends, parses revenue + estimated employees out of the
     XBRL, and recomputes `revenue_growth_bucket` across all sources at
     the end.

  Each stage logs its own duration; the orchestrator logs the total.
  """

  require Logger

  alias Colt.Services.Ingest.Fi.Prh.{
    AnnualReports,
    CompaniesImport,
    Download
  }

  @stages 3

  def run(opts \\ []) do
    started = System.monotonic_time(:millisecond)
    from = Keyword.get(opts, :from, 1)

    with {:ok, downloads} <-
           maybe_stage(1, from, "Downloading PRH companies dump", &Download.run/0),
         {:ok, companies} <-
           maybe_stage(2, from, "Importing companies (PRH NDJSON)", &CompaniesImport.run/0),
         {:ok, reports} <-
           maybe_stage(3, from, "Importing iXBRL annual reports", &AnnualReports.run/0) do
      cleanup_cache()
      Logger.info("PRH ingest finished in #{seconds(started)}s")

      {:ok,
       %{
         downloads: downloads,
         companies: companies,
         reports: reports
       }}
    end
  end

  # Wipe the PRH cache (just the all_companies zip today) after a full
  # successful ingest, so the Fly rootfs doesn't slowly fill up.
  defp cleanup_cache do
    dir = Application.fetch_env!(:colt, :prh_fi_cache_dir)
    abs_dir = if Path.type(dir) == :absolute, do: dir, else: Application.app_dir(:colt, dir)

    case File.ls(abs_dir) do
      {:ok, names} ->
        Enum.each(names, fn name ->
          _ = File.rm(Path.join(abs_dir, name))
        end)

        Logger.info("PRH cache cleared: #{abs_dir} (#{length(names)} files)")

      {:error, reason} ->
        Logger.warning("PRH cache cleanup skipped: #{inspect(reason)}")
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

  defp seconds(started) do
    div(System.monotonic_time(:millisecond) - started, 1000)
  end
end
