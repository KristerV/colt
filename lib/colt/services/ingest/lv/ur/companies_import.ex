NimbleCSV.define(Colt.Services.Ingest.Lv.Ur.CompaniesImport.CSV,
  separator: ";",
  escape: "\""
)

defmodule Colt.Services.Ingest.Lv.Ur.CompaniesImport do
  @moduledoc """
  Streams `register.csv` (Latvia's Uzņēmumu reģistrs basic-data dump) and
  upserts the registry-side fields (name, region, status) onto
  `Colt.Resources.Company` with `market: :lv`.

  Mirrors `Ee.Rik.CompaniesImport`: same per-row Ash `upsert_basic` in
  500-row chunks. ~480k rows fits comfortably within Ash's throughput at
  this size; raw-SQL is reserved for the multi-million-row annual reports
  stage.

  Columns we care about: `regcode`, `name`, `type` (legal form), `address`
  (first segment → region), `terminated` (non-empty → `:deleted`).
  """

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Lv.Ur.CompaniesImport.CSV
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @batch 500
  @filename "register.csv"

  def run do
    with {:ok, path} <- locate_file(),
         {:ok, count} <- stream_and_upsert(path) do
      {:ok, %{file: @filename, processed: count}}
    end
  end

  defp locate_file do
    dir = Application.fetch_env!(:colt, :ur_lv_cache_dir)
    path = Path.join(dir, @filename)

    if File.exists?(path), do: {:ok, path}, else: {:error, {:not_found, path}}
  end

  defp stream_and_upsert(path) do
    # `register.csv` is a UTF-8-with-BOM file, semicolon-separated, with
    # double-quoted fields that may contain embedded `;` (legal-name
    # variants love quotes). NimbleCSV's `parse_stream` opens the file
    # with `:file.open(:raw)` internally — same pattern documented in
    # `docs/large-csv-ingest.md` — so the file IO never becomes the
    # bottleneck at this size.
    headers =
      path
      |> File.stream!()
      |> Enum.take(1)
      |> case do
        [line] -> parse_header(line)
        [] -> []
      end

    count =
      path
      |> File.stream!(read_ahead: 256 * 1024)
      |> CSV.parse_stream(skip_headers: true)
      |> Progress.tick("register.csv rows read")
      |> Stream.map(&parse_row(&1, headers))
      |> Stream.reject(&is_nil/1)
      |> Stream.filter(&Sample.included?(&1.registry_code))
      |> Stream.chunk_every(@batch)
      |> Enum.reduce(0, fn chunk, n ->
        Ash.bulk_create!(chunk, Company, :upsert_basic,
          return_errors?: true,
          stop_on_error?: true
        )

        n + length(chunk)
      end)

    Progress.done("LV companies upserted", count)
    {:ok, count}
  end

  defp parse_header(line) do
    line
    |> String.replace_prefix("﻿", "")
    |> String.trim()
    |> String.split(";")
  end

  defp parse_row(fields, headers) when is_list(fields) do
    map = headers |> Enum.zip(fields) |> Map.new()
    code = map |> Map.get("regcode", "") |> String.trim()
    name = map |> Map.get("name", "") |> String.trim()

    if code == "" or name == "" do
      nil
    else
      %{
        registry_code: code,
        market: :lv,
        name: name,
        region: region_from_address(map["address"]),
        status: status_atom(map["terminated"], map["closed"])
      }
    end
  end

  # Address shape in UR data is: "<city/county>, <street>, <building>" e.g.
  # "Rīga, Avotu iela 17". First comma-separated segment is the locality.
  # Falls back to the whole string if there's no comma.
  defp region_from_address(nil), do: nil
  defp region_from_address(""), do: nil

  defp region_from_address(addr) do
    addr
    |> String.split(",", parts: 2)
    |> List.first()
    |> String.trim()
    |> case do
      "" -> nil
      v -> v
    end
  end

  # `terminated` is the deregistration date (`YYYY-MM-DD`) — non-empty means
  # the legal entity is gone. `closed` carries flags like "L" (liquidation).
  # Everything else is treated as registered. We don't bother decoding
  # the full status taxonomy; the downstream UI only cares about
  # registered vs not.
  defp status_atom(terminated, closed) do
    cond do
      present?(terminated) -> :deleted
      String.trim(to_string(closed)) == "L" -> :liquidation
      true -> :registered
    end
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(" "), do: false
  defp present?(s) when is_binary(s), do: String.trim(s) != ""
  defp present?(_), do: false
end
