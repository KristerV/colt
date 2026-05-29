defmodule Colt.Services.Ingest.Lt.Rc.CompaniesImport do
  @moduledoc """
  Streams `jar_iregistruoti.csv` (Lithuanian JAR basic registry, ~230k
  rows) and upserts every Lithuanian legal entity through
  `Company.upsert_basic`.

  File format (verified 2026-05-28):

      ja_kodas|ja_pavadinimas|adresas|ja_reg_data|form_kodas|form_pavadinimas|
      stat_kodas|stat_pavadinimas|stat_data_nuo|formavimo_data

  - `|`-delimited
  - UTF-8
  - Names are double-quote-escaped when they contain spaces; embedded
    `"` is doubled (`""`) — same convention as CSV.

  Per `docs/countries/lt.md`, JAR carries no NACE/EVRK code; companies
  are ingested with `industry_code = nil` for now.
  """

  require Logger

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @batch 500
  @filename "jar_iregistruoti.csv"

  def run do
    with {:ok, path} <- locate_file(),
         {:ok, count} <- stream_and_upsert(path) do
      {:ok, %{file: @filename, processed: count}}
    end
  end

  defp locate_file do
    dir = Application.fetch_env!(:colt, :rc_lt_cache_dir)
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
      |> Progress.tick("JAR rows read")
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

    Progress.done("LT companies upserted", count)
    {:ok, count}
  end

  defp parse_header(line) do
    line
    |> String.replace_prefix("﻿", "")
    |> String.trim()
    |> split_pipe()
  end

  defp parse_row(line, headers) do
    fields =
      line
      |> String.trim_trailing("\n")
      |> String.trim_trailing("\r")
      |> split_pipe()

    if length(fields) != length(headers) do
      nil
    else
      map = headers |> Enum.zip(fields) |> Map.new()
      code = map |> Map.get("ja_kodas", "") |> String.trim()
      name = map |> Map.get("ja_pavadinimas", "") |> unquote_field()

      cond do
        code == "" or name == "" ->
          nil

        not numeric?(code) ->
          nil

        true ->
          %{
            registry_code: code,
            market: :lt,
            name: name,
            region: parse_region(Map.get(map, "adresas")),
            status: status_atom(Map.get(map, "stat_kodas", ""))
          }
      end
    end
  end

  # Splits on `|` while respecting double-quoted fields (which may contain
  # literal pipes, though JAR doesn't in practice). Handles `""` as an
  # escaped quote inside a quoted field.
  defp split_pipe(line), do: do_split(line, [], <<>>, false)

  defp do_split(<<>>, acc, buf, _in_q), do: Enum.reverse([buf | acc])

  defp do_split(<<?", ?", rest::binary>>, acc, buf, true) do
    do_split(rest, acc, buf <> "\"", true)
  end

  defp do_split(<<?", rest::binary>>, acc, buf, in_q) do
    do_split(rest, acc, buf, not in_q)
  end

  defp do_split(<<?|, rest::binary>>, acc, buf, false) do
    do_split(rest, [buf | acc], <<>>, false)
  end

  defp do_split(<<c::utf8, rest::binary>>, acc, buf, in_q) do
    do_split(rest, acc, buf <> <<c::utf8>>, in_q)
  end

  # Fallback for non-UTF8 bytes — keep raw.
  defp do_split(<<c, rest::binary>>, acc, buf, in_q) do
    do_split(rest, acc, buf <> <<c>>, in_q)
  end

  defp unquote_field(nil), do: ""
  defp unquote_field(""), do: ""

  defp unquote_field(s) do
    s
    |> String.trim()
    |> String.replace("\"\"", "\"")
    |> trim_outer_quotes()
  end

  defp trim_outer_quotes(<<?", rest::binary>>) when byte_size(rest) >= 1 do
    case :binary.last(rest) do
      ?" -> :binary.part(rest, 0, byte_size(rest) - 1)
      _ -> "\"" <> rest
    end
  end

  defp trim_outer_quotes(s), do: s

  defp numeric?(""), do: false

  defp numeric?(s) do
    s
    |> String.to_charlist()
    |> Enum.all?(fn c -> c >= ?0 and c <= ?9 end)
  end

  # Address is `Region [sav., sen., …], Street, LT-XXXXX`. First
  # comma-segment is the region or municipality.
  defp parse_region(nil), do: nil
  defp parse_region(""), do: nil

  defp parse_region(addr) do
    addr
    |> unquote_field()
    |> String.split(",", parts: 2)
    |> List.first()
    |> case do
      nil -> nil
      "" -> nil
      first -> first |> String.trim() |> nil_if_empty()
    end
  end

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(s), do: s

  # See `docs/countries/lt.md` — `stat_kodas` mapping. Anything other
  # than the documented liquidation/deletion codes is `:registered` if
  # the operating-normally code (`0`), else `:other`.
  defp status_atom("0"), do: :registered
  defp status_atom("1"), do: :liquidation
  defp status_atom("2"), do: :liquidation
  defp status_atom("3"), do: :liquidation
  defp status_atom("4"), do: :deleted
  defp status_atom("5"), do: :deleted
  defp status_atom(_), do: :other
end
