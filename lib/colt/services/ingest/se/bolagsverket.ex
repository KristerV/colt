defmodule Colt.Services.Ingest.Se.Bolagsverket do
  @moduledoc """
  Orchestrates a full Bolagsverket ingest for the Swedish market.

  Stages (each its own service module under `Colt.Services.Ingest.Se.Bolagsverket.*`):

  1. `Auth` — fetch + cache an OAuth2 client-credentials access token for the
     "Värdefulla datamängder" (HVD) API. Reused by stages 2 and 3.
  2. `CompaniesImport` — page `POST /organisationer` and upsert every Swedish
     organisation through `Company.upsert_full`.
  3. `AnnualReports` — for each company, list its iXBRL filings via
     `POST /dokumentlista`, fetch the most recent (up to `:ingest_max_years`)
     via `GET /dokument/{id}`, parse revenue + average employees out of the
     iXBRL, convert SEK→EUR, and bulk-insert one `AnnualReport` per filing.
  4. `GrowthRollup` — recompute `revenue_latest` / `employees_latest` /
     `revenue_growth_bucket` across all sources (same SQL as EE/FI).

  Credentials live under `config :colt, :bolagsverket, client_id:, client_secret:`.
  When either is missing the orchestrator returns `{:error, :missing_api_key}`
  rather than crashing — matches the per-user-creds pattern used elsewhere
  for optional external services.

  Coverage caveat: Swedish iXBRL filing has only been *mandatory* since
  1 July 2024, so revenue+employees coverage is at ~50-70% of active ABs
  today and rising. See `docs/countries/se.md` for the honest breakdown.
  """

  require Logger

  alias Colt.Services.Ingest.Se.Bolagsverket.{
    AnnualReports,
    Auth,
    CompaniesImport,
    GrowthRollup
  }

  @stages 4

  def run(opts \\ []) do
    started = System.monotonic_time(:millisecond)
    from = Keyword.get(opts, :from, 1)

    with {:ok, token} <-
           maybe_stage(1, from, "Fetching Bolagsverket OAuth token", &Auth.run/0),
         {:ok, companies} <-
           maybe_stage(2, from, "Importing companies (HVD organisationer)", fn ->
             CompaniesImport.run(token)
           end),
         {:ok, reports} <-
           maybe_stage(3, from, "Importing iXBRL annual reports", fn ->
             AnnualReports.run(token)
           end),
         {:ok, growth} <-
           maybe_stage(4, from, "Recomputing growth rollup", &GrowthRollup.run/0) do
      Logger.info("Bolagsverket ingest finished in #{seconds(started)}s")

      {:ok,
       %{
         token: :ok,
         companies: companies,
         reports: reports,
         growth: growth
       }}
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
