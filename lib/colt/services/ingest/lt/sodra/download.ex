defmodule Colt.Services.Ingest.Lt.Sodra.Download do
  @moduledoc """
  Fetches the Sodra open-data ZIPs into the configured cache directory.

  The HTTP layer is **pluggable** because `atvira.sodra.lt` sits behind
  a managed Cloudflare interactive challenge (verified 2026-05-28; see
  `docs/countries/lt.md`). The orchestrator passes a `fetcher/1`
  function which takes a URL and returns `{:ok, binary}` or
  `{:error, reason}`.

  Default fetcher (in `Lt.Sodra`) returns
  `{:error, :sodra_blocked_by_cloudflare}` so the Oban job fails
  cleanly. Wire a CDP-backed fetcher (or proxy) once one is chosen.
  """

  require Logger

  @max_age_seconds 24 * 60 * 60

  # Per `docs/countries/lt.md` — dataset 1510 / dataset 1508.
  @sources [
    %{
      url: "https://atvira.sodra.lt/downloads/lt-eur/apdraustieji_det.zip",
      out: "apdraustieji_det.zip"
    },
    %{
      url: "https://atvira.sodra.lt/downloads/lt-eur/draudejai.zip",
      out: "draudejai.zip"
    }
  ]

  def run(fetcher) when is_function(fetcher, 1) do
    with {:ok, dir} <- ensure_cache_dir(),
         {:ok, results} <- fetch_each(dir, fetcher) do
      {:ok, %{dir: dir, files: results}}
    end
  end

  defp ensure_cache_dir do
    dir = Application.fetch_env!(:colt, :sodra_lt_cache_dir)
    File.mkdir_p!(dir)
    {:ok, dir}
  end

  defp fetch_each(dir, fetcher) do
    Enum.reduce_while(@sources, {:ok, []}, fn source, {:ok, acc} ->
      case do_fetch(source, dir, fetcher) do
        {:ok, status} ->
          {:cont, {:ok, [{source.out, status} | acc]}}

        {:error, reason} ->
          {:halt, {:error, {:sodra_download_failed, source.out, reason}}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      other -> other
    end
  end

  defp do_fetch(source, dir, fetcher) do
    out = Path.join(dir, source.out)

    if fresh?(out) do
      Logger.debug("Sodra download skipped (fresh): #{source.out}")
      {:ok, :ok}
    else
      Logger.info("Fetching #{source.url} via #{inspect(fetcher)}")

      case fetcher.(source.url) do
        {:ok, body} when is_binary(body) and byte_size(body) > 0 ->
          File.write!(out, body)
          {:ok, :ok}

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, {:unexpected_fetcher_response, other}}
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
