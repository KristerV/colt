defmodule Colt.Services.Ingest.Lt.Rc.Download do
  @moduledoc """
  Pulls the Registrų centras open-data CSVs into the configured cache
  directory. No auth, no Cloudflare challenge — direct HTTP from
  `www.registrucentras.lt/aduomenys/?byla=...`.

  Files refreshed within `@max_age_seconds` are skipped so re-running is
  cheap.

  See `docs/countries/lt.md` for the dataset list and licensing.
  """

  require Logger

  @max_age_seconds 6 * 60 * 60
  @base "https://www.registrucentras.lt/aduomenys/?byla="

  # Number of fiscal years of profit/loss data to keep. RC publishes
  # 2015→latest; we pull the last `@years_back` from `Date.utc_today/0`,
  # mirroring `Colt.Services.Ingest.Ee.Rik.Download` semantics. `optional?`
  # downloads silently skip on 404 (RC publishes the previous-FY file a
  # few months into the next calendar year).
  @years_back 5

  @sources [
    %{
      url: @base <> "JAR_IREGISTRUOTI.csv",
      out: "jar_iregistruoti.csv",
      optional?: false
    }
  ]

  def run do
    with {:ok, dir} <- ensure_cache_dir(),
         {:ok, sources} <- expand_sources(),
         {:ok, results} <- fetch_each(sources, dir) do
      {:ok, %{dir: dir, files: results}}
    end
  end

  defp ensure_cache_dir do
    dir = Application.fetch_env!(:colt, :rc_lt_cache_dir)
    File.mkdir_p!(dir)
    {:ok, dir}
  end

  defp expand_sources do
    today = Date.utc_today()
    # Latest fully-filed year is roughly current_year - 1; the file may
    # only appear several months into the next calendar year, hence
    # `optional?: true`.
    earliest = today.year - @years_back
    years = (today.year - 1)..earliest//-1 |> Enum.to_list()

    year_sources =
      Enum.map(years, fn year ->
        %{
          url: @base <> "JAR_FA_RODIKLIAI_PLNA_#{year}.csv",
          out: "plna_#{year}.csv",
          optional?: true
        }
      end)

    {:ok, @sources ++ year_sources}
  end

  defp fetch_each(sources, dir) do
    results =
      Enum.map(sources, fn source ->
        case do_fetch(source, dir) do
          {:ok, :ok} ->
            {source.out, :ok}

          {:error, {:http_status, status, _}} when status in [404, 410] ->
            if Map.get(source, :optional?, false) do
              Logger.info("Skipping #{source.out}: not available (#{status})")
              {source.out, :skipped}
            else
              {source.out, {:error, {:http_status, status, source.url}}}
            end

          {:error, reason} ->
            {source.out, {:error, reason}}
        end
      end)

    failed = Enum.filter(results, fn {_, status} -> match?({:error, _}, status) end)

    if failed == [], do: {:ok, results}, else: {:error, {:downloads_failed, failed}}
  end

  defp do_fetch(source, dir) do
    out = Path.join(dir, source.out)

    if fresh?(out) do
      Logger.debug("RC LT download skipped (fresh): #{source.out}")
      {:ok, :ok}
    else
      Logger.info("Downloading #{source.url}")

      case Req.get(source.url,
             into: File.stream!(out),
             receive_timeout: 600_000,
             retry: :transient
           ) do
        {:ok, %{status: 200}} ->
          if html?(out) do
            _ = File.rm(out)
            {:error, {:http_status, 404, source.url}}
          else
            {:ok, :ok}
          end

        {:ok, %{status: status}} ->
          _ = File.rm(out)
          {:error, {:http_status, status, source.url}}

        {:error, reason} ->
          _ = File.rm(out)
          {:error, reason}
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

  # RC's `aduomenys/` endpoint sometimes returns 200 + an HTML error page
  # when the file isn't available. Detect via the leading bytes.
  defp html?(path) do
    case File.open(path, [:read, :raw], fn fd -> :file.read(fd, 16) end) do
      {:ok, {:ok, head}} ->
        head_str = head |> to_string() |> String.downcase()
        String.starts_with?(head_str, "<!doctype") or String.starts_with?(head_str, "<html")

      _ ->
        false
    end
  end
end
