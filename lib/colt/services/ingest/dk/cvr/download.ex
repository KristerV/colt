defmodule Colt.Services.Ingest.Dk.Cvr.Download do
  @moduledoc """
  Stub stage for the CVR/Virk ingest.

  Denmark publishes no free bulk dump of the company registry — the
  `cvr-permanent` Elasticsearch index requires a 3-week-approval
  system-til-system credential. The public regnskaber feed is
  per-filing, not a single archive.

  This module exists only to preserve the staged-resume contract used
  by the orchestrator (`run(from: N)`). It ensures the cache directory
  exists and returns immediately.
  """

  require Logger

  def run do
    dir = Application.get_env(:colt, :cvr_dk_cache_dir, "priv/ingest_cache_dk")
    File.mkdir_p!(dir)
    Logger.info("CVR has no bulk dump; skipping download stage.")
    {:ok, %{status: :no_bulk_download, dir: dir}}
  end
end
