defmodule Colt.Services.Ingest.Ee.Rik.CompaniesImport do
  @moduledoc """
  Streams `lihtandmed.csv` (Estonian business registry "basic data") and
  upserts the registry-side fields (name, region, status) onto
  `Colt.Resources.Company`.
  """

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @batch 500
  @filename "lihtandmed.csv"

  def run do
    with {:ok, path} <- locate_file(),
         {:ok, count} <- stream_and_upsert(path) do
      {:ok, %{file: @filename, processed: count}}
    end
  end

  defp locate_file do
    dir = Application.fetch_env!(:colt, :rik_ee_cache_dir)
    path = Path.join(dir, @filename)

    if File.exists?(path), do: {:ok, path}, else: {:error, {:not_found, path}}
  end

  defp stream_and_upsert(path) do
    [header_line] = path |> File.stream!() |> Enum.take(1)
    headers = parse_header(header_line)

    count =
      path
      |> File.stream!()
      |> Stream.drop(1)
      |> Progress.tick("lihtandmed rows read")
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

    Progress.done("companies upserted", count)
    {:ok, count}
  end

  defp parse_header(line) do
    line
    |> String.replace_prefix("﻿", "")
    |> String.trim()
    |> String.split(";")
  end

  defp parse_row(line, headers) do
    fields =
      line
      |> String.trim_trailing("\n")
      |> String.trim_trailing("\r")
      |> String.split(";")

    map = headers |> Enum.zip(fields) |> Map.new()
    code = map |> Map.get("ariregistri_kood", "") |> String.trim()
    name = map |> Map.get("nimi", "") |> String.trim()

    if code == "" or name == "" do
      nil
    else
      %{
        registry_code: code,
        market: :ee,
        name: name,
        region: blank_to_nil(map["asukoha_ehak_tekstina"]),
        status: status_atom(map["ettevotja_staatus"])
      }
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: String.trim(s)

  defp status_atom("R"), do: :registered
  defp status_atom("L"), do: :liquidation
  defp status_atom("N"), do: :deleted
  defp status_atom(_), do: :other
end
