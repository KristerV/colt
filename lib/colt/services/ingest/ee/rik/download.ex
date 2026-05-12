defmodule Colt.Services.Ingest.Ee.Rik.Download do
  @moduledoc """
  Pulls the rik.ee Avaandmed dumps into the configured cache directory and
  unzips them. Files refreshed within `@max_age_seconds` are skipped, so
  re-running is cheap.

  See spec §3.2 for the procedure on third-party services. Sources:
  https://avaandmed.ariregister.rik.ee/et/avaandmete-allalaadimine
  """

  require Logger

  @max_age_seconds 6 * 60 * 60

  @base "https://avaandmed.ariregister.rik.ee/sites/default/files"

  @sources [
    %{
      url: "#{@base}/avaandmed/ettevotja_rekvisiidid__lihtandmed.csv.zip",
      zip: "lihtandmed.csv.zip",
      member: "ettevotja_rekvisiidid__lihtandmed.csv",
      out: "lihtandmed.csv"
    },
    %{
      url: "#{@base}/avaandmed/ettevotja_rekvisiidid__yldandmed.json.zip",
      zip: "yldandmed.json.zip",
      member: "ettevotja_rekvisiidid__yldandmed.json",
      out: "yldandmed.json"
    },
    %{
      url: "#{@base}/1.aruannete_yldandmed_kuni_30042026.zip",
      zip: "aruannete_yldandmed.zip",
      member_pattern: ~r/^1\.aruannete_yldandmed_kuni_.*\.csv$/,
      out: "aruannete_yldandmed.csv"
    }
    # plus per-year elemendid_YYYY built dynamically below
  ]

  def run do
    with {:ok, dir} <- ensure_cache_dir(),
         {:ok, sources} <- expand_sources(),
         {:ok, results} <- fetch_each(sources, dir) do
      {:ok, %{dir: dir, files: results}}
    end
  end

  defp ensure_cache_dir do
    dir = Application.fetch_env!(:colt, :rik_ee_cache_dir)
    File.mkdir_p!(dir)
    {:ok, dir}
  end

  # RIK publishes one elemendid_YYYY zip per fiscal year. The earliest year
  # available as of 2026-05 is 2019 — see
  # https://avaandmed.ariregister.rik.ee/et/avaandmete-allalaadimine.
  # `@earliest_year` is intentionally permissive: we try a year earlier than
  # known-available so RIK can add older years without a code change. Any
  # year whose zip 404s is skipped — failed downloads don't abort the run.
  @earliest_year 2018

  defp expand_sources do
    today = Date.utc_today()
    years = (today.year - 1)..@earliest_year//-1 |> Enum.to_list()

    year_sources =
      Enum.map(years, fn year ->
        %{
          url: "#{@base}/4.#{year}_aruannete_elemendid_kuni_30042026.zip",
          zip: "elemendid_#{year}.zip",
          member_pattern: ~r/^4\.#{year}_aruannete_elemendid_kuni_.*\.csv$/,
          out: "elemendid_#{year}.csv",
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

          {:error, {:http_status, 404, _}} ->
            if Map.get(source, :optional?, false) do
              Logger.info("Skipping #{source.out}: not available from RIK")
              {source.out, :skipped}
            else
              {source.out, {:error, {:http_status, 404, source.url}}}
            end

          {:error, reason} ->
            {source.out, {:error, reason}}
        end
      end)

    failed = Enum.filter(results, fn {_, status} -> match?({:error, _}, status) end)

    if failed == [], do: {:ok, results}, else: {:error, {:downloads_failed, failed}}
  end

  defp do_fetch(source, dir) do
    with {:ok, :ok} <- maybe_download(source, dir),
         {:ok, :ok} <- maybe_unzip(source, dir) do
      {:ok, :ok}
    end
  end

  defp maybe_download(source, dir) do
    zip_path = Path.join(dir, source.zip)
    out_path = Path.join(dir, source.out)

    cond do
      fresh?(out_path) ->
        Logger.debug("Download skipped (extracted file fresh): #{source.out}")
        {:ok, :ok}

      fresh?(zip_path) ->
        Logger.debug("Download skipped (zip fresh): #{source.zip}")
        {:ok, :ok}

      true ->
        Logger.info("Downloading #{source.url}")
        do_download(source.url, zip_path)
    end
  end

  defp do_download(url, path) do
    case Req.get(url, into: File.stream!(path), receive_timeout: 600_000, retry: :transient) do
      {:ok, %{status: 200}} -> {:ok, :ok}
      {:ok, %{status: status}} -> {:error, {:http_status, status, url}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_unzip(source, dir) do
    out = Path.join(dir, source.out)

    if fresh?(out) do
      Logger.debug("Unzip skipped (fresh): #{source.out}")
      {:ok, :ok}
    else
      do_unzip(source, dir)
    end
  end

  defp do_unzip(source, dir) do
    zip = Path.join(dir, source.zip)
    out = Path.join(dir, source.out)

    case :zip.list_dir(String.to_charlist(zip)) do
      {:ok, entries} ->
        member = pick_member(source, entries)

        if member do
          case :zip.unzip(String.to_charlist(zip),
                 file_list: [member],
                 cwd: String.to_charlist(dir)
               ) do
            {:ok, _} ->
              extracted = Path.join(dir, to_string(member))
              if extracted != out, do: File.rename!(extracted, out)
              _ = File.rm(zip)
              {:ok, :ok}

            {:error, reason} ->
              {:error, {:unzip_failed, reason}}
          end
        else
          {:error, {:no_member_match, source.zip}}
        end

      {:error, reason} ->
        {:error, {:zip_list_failed, reason}}
    end
  end

  defp pick_member(%{member: name}, _entries), do: String.to_charlist(name)

  defp pick_member(%{member_pattern: pattern}, entries) do
    Enum.find_value(entries, fn
      {:zip_file, name, _, _, _, _} ->
        name_str = to_string(name)
        if Regex.match?(pattern, name_str), do: String.to_charlist(name_str)

      _ ->
        nil
    end)
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
