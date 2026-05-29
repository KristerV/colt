defmodule Colt.Services.Ingest.No.Brreg.Download do
  @moduledoc """
  Pulls the BRREG `enheter_alle.csv.gz` bulk dump into the cache directory.
  Files refreshed within `@max_age_seconds` are skipped so re-running is
  cheap. We keep the `.gz` on disk (stage 2 streams gzip directly via
  `:zlib`); no unzip step.

  Source: `https://data.brreg.no/enhetsregisteret/api/enheter/lastned/csv`
  Licence: NLOD 2.0. No auth. Dump regenerated nightly ~05:00 CEST.
  """

  require Logger

  @max_age_seconds 6 * 60 * 60
  @gz_filename "enheter_alle.csv.gz"
  @csv_filename "enheter_alle.csv"
  @url "https://data.brreg.no/enhetsregisteret/api/enheter/lastned/csv"

  def run do
    with {:ok, dir} <- ensure_cache_dir(),
         {:ok, _gz} <- maybe_download(dir),
         {:ok, csv} <- maybe_gunzip(dir) do
      {:ok, %{dir: dir, files: [{@gz_filename, :ok}, {@csv_filename, :ok}], path: csv}}
    end
  end

  defp ensure_cache_dir do
    dir = Application.fetch_env!(:colt, :brreg_no_cache_dir)
    File.mkdir_p!(dir)
    {:ok, dir}
  end

  defp maybe_download(dir) do
    gz = Path.join(dir, @gz_filename)
    csv = Path.join(dir, @csv_filename)

    cond do
      fresh?(csv) ->
        Logger.debug("BRREG download skipped (csv fresh): #{@csv_filename}")
        {:ok, gz}

      fresh?(gz) ->
        Logger.debug("BRREG download skipped (gz fresh): #{@gz_filename}")
        {:ok, gz}

      true ->
        Logger.info("Downloading #{@url}")
        do_download(gz)
    end
  end

  defp maybe_gunzip(dir) do
    gz = Path.join(dir, @gz_filename)
    csv = Path.join(dir, @csv_filename)

    cond do
      fresh?(csv) ->
        Logger.debug("BRREG gunzip skipped (fresh): #{@csv_filename}")
        {:ok, csv}

      File.exists?(gz) ->
        Logger.info("Gunzipping #{@gz_filename}")
        do_gunzip(gz, csv)

      true ->
        {:error, {:gz_missing, gz}}
    end
  end

  # Stream-gunzip to disk: avoids holding the ~800 MB uncompressed CSV in
  # memory. Reads 256 KB at a time through a `:zlib` stream handle.
  defp do_gunzip(gz_path, csv_path) do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z, 31)

    in_fd = File.open!(gz_path, [:read, :raw, :binary, {:read_ahead, 256 * 1024}])
    out_fd = File.open!(csv_path, [:write, :raw, :binary, {:delayed_write, 256 * 1024, 1_000}])

    try do
      pump_inflate(z, in_fd, out_fd)
      {:ok, csv_path}
    after
      :ok = :zlib.inflateEnd(z)
      :ok = :zlib.close(z)
      File.close(in_fd)
      File.close(out_fd)
      # Keep the .gz on disk; cleanup at orchestrator level wipes both.
    end
  end

  defp pump_inflate(z, in_fd, out_fd) do
    case :file.read(in_fd, 256 * 1024) do
      {:ok, chunk} ->
        chunks = :zlib.inflate(z, chunk)
        Enum.each(chunks, fn part -> :ok = :file.write(out_fd, part) end)
        pump_inflate(z, in_fd, out_fd)

      :eof ->
        :ok
    end
  end

  defp do_download(path) do
    # Oban owns retry semantics for the worker; Req's transient retry is
    # fine for a single ~150 MB GET (it doesn't honour Retry-After up to
    # 1h because we won't get one here).
    case Req.get(@url,
           into: File.stream!(path),
           receive_timeout: 600_000,
           retry: :transient
         ) do
      {:ok, %{status: 200}} ->
        {:ok, path}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status, @url}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fresh?(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} ->
        System.system_time(:second) - mtime < @max_age_seconds

      _ ->
        false
    end
  end
end
