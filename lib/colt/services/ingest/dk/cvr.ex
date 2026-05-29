defmodule Colt.Services.Ingest.Dk.Cvr do
  @moduledoc """
  Orchestrates a full CVR / Virk ingest for the Danish market.

  Unlike EE/RIK and FI/PRH, Denmark does **not** publish a free bulk
  company-registry dump. The auth-gated `distribution.virk.dk/cvr-permanent`
  index requires a 3-week-approval credential we don't have.

  What is free and public is `distribution.virk.dk/offentliggoerelser` —
  the annual-report (regnskab / årsrapport) index, including XBRL doc URLs
  hosted at `regnskaber.virk.dk`. The XBRL header carries the CVR number,
  legal name, and address; the financial body carries `fsa:Revenue` (only
  for Class C+ filers, ~12% coverage) and `fsa:AverageNumberOfEmployees`
  (most filers above the micro threshold, ~81% coverage).

  Pipeline:

  1. `Download` — no-op stub (no bulk dump exists). Returns
     `{:ok, :no_bulk_download}` so the `from: N` resume contract works
     the same as the other countries.
  2. `AnnualReports` — scrolls the public Elasticsearch index, fetches +
     parses each XBRL, and upserts both the parent `Company` (identity
     only, no industry — we have no source for branchekode without the
     auth-gated CVR registry) and one `AnnualReport` per (company, year).
  3. `GrowthRollup` — same SQL pass as EE/FI, source-agnostic.

  See `docs/countries/dk.md` for coverage, sampling, and the full source
  catalogue. See `docs/large-csv-ingest.md` for why the bulk insert is
  raw SQL and not `Ash.bulk_create`.
  """

  require Logger

  alias Colt.Services.Ingest.Dk.Cvr.{AnnualReports, Download, GrowthRollup}

  @stages 3

  def run(opts \\ []) do
    started = System.monotonic_time(:millisecond)
    from = Keyword.get(opts, :from, 1)

    with {:ok, downloads} <-
           maybe_stage(1, from, "Download stub (CVR has no bulk dump)", &Download.run/0),
         {:ok, reports} <-
           maybe_stage(2, from, "Importing annual reports (CVR/Virk XBRL)", fn ->
             AnnualReports.run(opts)
           end),
         {:ok, growth} <-
           maybe_stage(3, from, "Recomputing growth rollup", &GrowthRollup.run/0) do
      cleanup_cache()
      Logger.info("CVR ingest finished in #{seconds(started)}s")

      {:ok,
       %{
         downloads: downloads,
         reports: reports,
         growth: growth
       }}
    end
  end

  defp cleanup_cache do
    dir = Application.get_env(:colt, :cvr_dk_cache_dir, "priv/ingest_cache_dk")
    abs_dir = if Path.type(dir) == :absolute, do: dir, else: Application.app_dir(:colt, dir)

    case File.ls(abs_dir) do
      {:ok, names} ->
        Enum.each(names, fn name -> _ = File.rm(Path.join(abs_dir, name)) end)
        Logger.info("CVR cache cleared: #{abs_dir} (#{length(names)} files)")

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Logger.warning("CVR cache cleanup skipped: #{inspect(reason)}")
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
