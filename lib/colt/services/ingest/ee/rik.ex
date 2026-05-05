defmodule Colt.Services.Ingest.Ee.Rik do
  @moduledoc """
  Orchestrates a full rik.ee Avaandmed ingest for the Estonian market.

  Steps (each is its own service module under `Colt.Services.Ingest.Ee.Rik.*`):

  1. `Download` — pulls + unzips the published dumps into the cache directory.
  2. `CompaniesImport` — upserts every Estonian company from `lihtandmed.csv`.
  3. `CompanyDetails` — patches website / industry / generic email from
     `yldandmed.json` onto the rows imported in step 2.
  4. `AnnualReports` — upserts the last three filed fiscal years and recomputes
     `revenue_growth_bucket` per company.
  """

  require Logger

  alias Colt.Services.Ingest.Ee.Rik.{
    AnnualReports,
    CompaniesImport,
    CompanyDetails,
    Download
  }

  @stages 4

  def run(opts \\ []) do
    started = System.monotonic_time(:millisecond)
    from = Keyword.get(opts, :from, 1)

    with {:ok, downloads} <- maybe_stage(1, from, "Downloading rik.ee dumps", &Download.run/0),
         {:ok, companies} <-
           maybe_stage(2, from, "Importing companies (lihtandmed.csv)", &CompaniesImport.run/0),
         {:ok, details} <-
           maybe_stage(3, from, "Patching details (yldandmed.json)", &CompanyDetails.run/0),
         {:ok, reports} <-
           maybe_stage(4, from, "Importing annual reports + growth", &AnnualReports.run/0) do
      Logger.info("Ingest finished in #{seconds(started)}s")

      {:ok,
       %{
         downloads: downloads,
         companies: companies,
         details: details,
         reports: reports
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
