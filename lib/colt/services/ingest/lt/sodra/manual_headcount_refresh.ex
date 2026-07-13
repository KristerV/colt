defmodule Colt.Services.Ingest.Lt.Sodra.ManualHeadcountRefresh do
  @moduledoc """
  Refreshes Lithuanian company employee counts from a **manually uploaded**
  Sodra open-data ZIP (per-employer insured persons).

  The automated `Download` stage is blocked by Cloudflare on
  `atvira.sodra.lt` (see `docs/countries/lt.md`), so an admin downloads the
  ZIP by hand from https://atvira.sodra.lt/ and uploads it. This service
  skips the download and runs only the two stages that turn the file into
  visible headcounts:

  1. `HeadcountImport` — upsert `annual_reports.employees` from the ZIP.
  2. `GrowthRollup` — project the new counts onto `companies.employees_latest`.

  The caller owns the uploaded file's lifecycle (delete after `run/1`).
  """

  alias Colt.Services.Ingest.Ee.Rik.GrowthRollup
  alias Colt.Services.Ingest.Lt.Sodra.HeadcountImport

  def run(zip_path) when is_binary(zip_path) do
    with {:ok, %{processed: processed}} <- HeadcountImport.run(zip_path),
         {:ok, %{updated: updated}} <- GrowthRollup.run() do
      {:ok, %{processed: processed, updated: updated}}
    end
  end
end
