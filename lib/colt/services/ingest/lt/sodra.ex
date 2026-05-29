defmodule Colt.Services.Ingest.Lt.Sodra do
  @moduledoc """
  Orchestrates the Sodra (Lithuania state social insurance) ingest of
  per-employer monthly headcount. Best free headcount source of any
  country we support — once we can actually download the files.

  See `docs/countries/lt.md` for the Cloudflare blocker on
  `atvira.sodra.lt` and the three production options:

  1. CDP fetch through Colt's existing chromium
  2. External CF-solving proxy
  3. Allowlist request to Sodra

  The pipeline is wired but the default fetcher is a stub that returns
  `{:error, :sodra_blocked_by_cloudflare}`. Pass a real fetcher in opts
  (or wire one via `config :colt, Colt.Services.Ingest.Lt.Sodra,
  fetcher: &MyMod.fetch/1`) once a solution is picked.

  Headcount is merged onto the existing `(company_id, year)`
  `AnnualReport` row created by `Lt.Rc.AnnualReports`. See
  `HeadcountImport` for the UPSERT shape.
  """

  require Logger

  alias Colt.Services.Ingest.Ee.Rik.GrowthRollup
  alias Colt.Services.Ingest.Lt.Sodra.{Download, HeadcountImport}

  @stages 3

  def run(opts \\ []) do
    started = System.monotonic_time(:millisecond)
    from = Keyword.get(opts, :from, 1)
    fetcher = Keyword.get(opts, :fetcher, fetcher_from_config())

    with {:ok, downloads} <-
           maybe_stage(1, from, "Downloading Sodra dumps", fn -> Download.run(fetcher) end),
         {:ok, headcounts} <-
           maybe_stage(2, from, "Importing Sodra headcount", &HeadcountImport.run/0),
         {:ok, growth} <-
           maybe_stage(3, from, "Recomputing growth rollup", &GrowthRollup.run/0) do
      cleanup_cache()
      Logger.info("Sodra LT ingest finished in #{seconds(started)}s")

      {:ok, %{downloads: downloads, headcounts: headcounts, growth: growth}}
    end
  end

  defp fetcher_from_config do
    case Application.get_env(:colt, __MODULE__, [])[:fetcher] do
      fun when is_function(fun, 1) -> fun
      _ -> &default_fetcher/1
    end
  end

  # Default fetcher: documents the blocker, does not attempt the request.
  # Replace via `opts` or app env once a real downloader exists.
  defp default_fetcher(_url) do
    {:error, :sodra_blocked_by_cloudflare}
  end

  defp cleanup_cache do
    dir = Application.fetch_env!(:colt, :sodra_lt_cache_dir)
    abs_dir = if Path.type(dir) == :absolute, do: dir, else: Application.app_dir(:colt, dir)

    case File.ls(abs_dir) do
      {:ok, names} ->
        Enum.each(names, fn name -> _ = File.rm(Path.join(abs_dir, name)) end)
        Logger.info("Sodra LT cache cleared: #{abs_dir} (#{length(names)} files)")

      {:error, reason} ->
        Logger.warning("Sodra LT cache cleanup skipped: #{inspect(reason)}")
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
