defmodule Colt.Services.Ingest.Lt.Sodra do
  @moduledoc """
  Ingests per-company Lithuanian data from Sodra's open company-data API
  (`atvira.sodra.lt/imones-rest/solr/page`) — the best free source in the region,
  giving **both** employee headcount **and** the EVRK/NACE code for every active
  employer (~49k companies).

  The API is behind a Cloudflare managed challenge, so it is reached through the
  stealth browser sidecar (`Colt.Services.Browser`). See `browser/README.md` for why
  a stealth-patched, headed-under-Xvfb browser is required (plain Req and stock
  headless chromium are both blocked).

  Pipeline:

    1. `Harvest` — page the JSON API through the browser → in-memory rows.
    2. `Import`  — upsert `annual_reports.employees` (source `:sodra`) and
       `companies.industry_code` (EVRK/NACE).
    3. `GrowthRollup` — project `employees_latest` from the new annual-report rows.

  (Supersedes the old zip-download approach: the `atvira.sodra.lt/downloads/*.zip`
  files are aggregate statistics with no company codes — they cannot populate
  per-company headcount. See git history / docs/countries/lt.md.)
  """

  require Logger

  alias Colt.Services.Ingest.Ee.Rik.GrowthRollup
  alias Colt.Services.Ingest.Lt.Sodra.{Harvest, Import}

  def run(opts \\ []) do
    started = System.monotonic_time(:millisecond)
    Logger.info("Sodra LT ingest starting")

    with {:ok, rows} <- Harvest.run(opts),
         :ok <- log_stage(1, "harvested #{length(rows)} company rows"),
         {:ok, imported} <- Import.run(rows),
         :ok <- log_stage(2, "imported #{inspect(imported)}"),
         {:ok, growth} <- GrowthRollup.run() do
      log_stage(3, "growth rollup #{inspect(growth)}")
      Logger.info("Sodra LT ingest finished in #{seconds(started)}s")
      {:ok, %{harvested: length(rows), import: imported, growth: growth}}
    end
  end

  defp log_stage(n, msg) do
    Logger.info("[#{n}/3] #{msg}")
    :ok
  end

  defp seconds(started_ms) do
    ((System.monotonic_time(:millisecond) - started_ms) / 1000) |> Float.round(1)
  end
end
