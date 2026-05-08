defmodule Colt.Services.Ingest.Fi.Prh.Download do
  @moduledoc """
  Pulls the PRH (Finnish Patent and Registration Office) `/all_companies`
  open-data dump into the configured cache directory. Files refreshed
  within `@max_age_seconds` are skipped so re-running is cheap.

  Source: https://avoindata.prh.fi/opendata-ytj-api/v3/all_companies — a
  ~95 MB ZIP containing one ~1.4 GB JSON array. The companion module
  `CompaniesImport` streams the array straight off `unzip -p`'s stdout,
  so we don't materialise the unzipped JSON or any NDJSON intermediate.
  """

  require Logger

  @url "https://avoindata.prh.fi/opendata-ytj-api/v3/all_companies"
  @zip "all_companies.zip"
  @max_age_seconds 6 * 60 * 60

  def run do
    with {:ok, dir} <- ensure_cache_dir(),
         {:ok, _} <- maybe_download(dir) do
      {:ok, %{dir: dir, file: @zip}}
    end
  end

  defp ensure_cache_dir do
    dir = Application.fetch_env!(:colt, :prh_fi_cache_dir)
    File.mkdir_p!(dir)
    {:ok, dir}
  end

  defp maybe_download(dir) do
    path = Path.join(dir, @zip)

    if fresh?(path) do
      Logger.debug("PRH zip download skipped (fresh): #{@zip}")
      {:ok, :ok}
    else
      Logger.info("Downloading #{@url}")

      case Req.get(@url, into: File.stream!(path), receive_timeout: 600_000, retry: :transient) do
        {:ok, %{status: 200}} -> {:ok, :ok}
        {:ok, %{status: status}} -> {:error, {:http_status, status, @url}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fresh?(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime, size: size}} ->
        size > 0 and System.system_time(:second) - mtime < @max_age_seconds

      _ ->
        false
    end
  end
end
