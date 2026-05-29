defmodule Colt.Services.Ingest.Lv.Ur.Download do
  @moduledoc """
  Fetches the three CC0-1.0 CSVs published by Uzņēmumu reģistrs on
  `data.gov.lv` into the configured cache directory. Files refreshed
  within `@max_age_seconds` are skipped so re-running is cheap.

  No auth, no zip; CSVs are served directly. See `docs/countries/lv.md`
  for the source list and licence.
  """

  require Logger

  @max_age_seconds 6 * 60 * 60

  @sources [
    %{
      url:
        "https://data.gov.lv/dati/dataset/4de9697f-850b-45ec-8bba-61fa09ce932f/resource/25e80bf3-f107-4ab4-89ef-251b5b9374e9/download/register.csv",
      out: "register.csv"
    },
    %{
      url:
        "https://data.gov.lv/dati/dataset/8d31b878-536a-44aa-a013-8bc6b669d477/resource/27fcc5ec-c63b-4bfd-bb08-01f073a52d04/download/financial_statements.csv",
      out: "financial_statements.csv"
    },
    %{
      url:
        "https://data.gov.lv/dati/dataset/8d31b878-536a-44aa-a013-8bc6b669d477/resource/d5fd17ef-d32e-40cb-8399-82b780095af0/download/income_statements.csv",
      out: "income_statements.csv"
    }
  ]

  def run do
    with {:ok, dir} <- ensure_cache_dir(),
         {:ok, results} <- fetch_each(dir) do
      {:ok, %{dir: dir, files: results}}
    end
  end

  defp ensure_cache_dir do
    dir = Application.fetch_env!(:colt, :ur_lv_cache_dir)
    File.mkdir_p!(dir)
    {:ok, dir}
  end

  defp fetch_each(dir) do
    results = Enum.map(@sources, &do_fetch(&1, dir))
    failed = Enum.filter(results, fn {_, status} -> match?({:error, _}, status) end)
    if failed == [], do: {:ok, results}, else: {:error, {:downloads_failed, failed}}
  end

  defp do_fetch(%{url: url, out: out}, dir) do
    path = Path.join(dir, out)

    if fresh?(path) do
      Logger.debug("UR download skipped (fresh): #{out}")
      {out, :ok}
    else
      Logger.info("Downloading #{url}")

      case Req.get(url, into: File.stream!(path), receive_timeout: 600_000, retry: :transient) do
        {:ok, %{status: 200}} -> {out, :ok}
        {:ok, %{status: status}} -> {out, {:error, {:http_status, status, url}}}
        {:error, reason} -> {out, {:error, reason}}
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
