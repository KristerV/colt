defmodule Colt.Bench.AnnualReportsParse do
  @moduledoc false
  # Bench harness for the elemendid CSV parser used by stage 4 of the EE RIK
  # ingest. Ships in the release so it can be invoked from remote iex without
  # a fresh deploy each time.
  #
  # In remote iex:
  #
  #   alias Colt.Bench.AnnualReportsParse, as: B
  #   B.run("priv/ingest_cache/elemendid_2023.csv", 200_000)
  #   B.run("priv/ingest_cache/elemendid_2023.csv", 800_000,
  #         fat: "priv/ingest_cache/aruannete_yldandmed.csv")
  #
  # Times only the parse + classify + reduce step. DB writes are excluded.

  alias Colt.Services.Ingest.Ee.Rik.AnnualReports

  @full_elemendid_2023_rows 3_726_716

  def run(elemendid_path, n, opts \\ []) do
    fat_path = Keyword.get(opts, :fat)

    unless File.exists?(elemendid_path) do
      IO.puts(:stderr, "source not found: #{elemendid_path}")
      throw(:halt)
    end

    dst = Path.join(System.tmp_dir!(), "bench_elemendid_#{n}.csv")
    bytes = slice(elemendid_path, dst, n)

    IO.puts("source : #{elemendid_path}")
    IO.puts("slice  : #{dst}  (#{Float.round(bytes / 1024 / 1024, 2)} MB, #{n} rows)")

    index =
      case fat_path do
        nil -> permissive_index(dst)
        path -> fat_index(path)
      end

    IO.puts("index  : #{map_size(index)} entries (#{if fat_path, do: "fat", else: "light"})")

    mem_before = :erlang.memory()
    print_heap("heap before", mem_before)

    _ = AnnualReports.collect_values(dst, index)
    :erlang.garbage_collect()

    {us, acc} = :timer.tc(fn -> AnnualReports.collect_values(dst, index) end)

    mem_after = :erlang.memory()
    secs = us / 1_000_000
    rows_per_sec = n / secs
    mb_per_sec = bytes / 1024 / 1024 / secs

    IO.puts("")
    IO.puts("elapsed       : #{Float.round(us / 1000, 1)} ms")
    IO.puts("rows / sec    : #{:erlang.float_to_binary(rows_per_sec, decimals: 0)}")
    IO.puts("MB / sec      : #{Float.round(mb_per_sec, 1)}")
    IO.puts("kept reports  : #{map_size(acc)}")
    print_heap("heap after ", mem_after)

    IO.puts("")

    IO.puts(
      "projected full elemendid_2023.csv (#{@full_elemendid_2023_rows} rows): " <>
        "#{Float.round(@full_elemendid_2023_rows / rows_per_sec, 1)} s"
    )

    :ok
  end

  defp slice(src, dst, n) do
    File.open!(dst, [:write, :binary], fn out ->
      src
      |> File.stream!()
      |> Stream.take(n + 1)
      |> Enum.each(&IO.binwrite(out, &1))
    end)

    %File.Stat{size: bytes} = File.stat!(dst)
    bytes
  end

  defp permissive_index(path) do
    path
    |> File.stream!()
    |> Stream.drop(1)
    |> Stream.flat_map(fn line ->
      case :binary.split(line, ";") do
        [rid, _] -> [String.trim(rid)]
        _ -> []
      end
    end)
    |> Enum.into(MapSet.new())
    |> Map.new(fn rid -> {rid, %{registry_code: rid, year: 2023}} end)
  end

  defp fat_index(overview_path) do
    IO.puts("building fat index from #{overview_path} …")

    {us, m} =
      :timer.tc(fn ->
        alias Colt.Services.Ingest.Ee.Rik.AnnualReports.CSV

        [header_line] = overview_path |> File.stream!() |> Enum.take(1)
        [headers] = CSV.parse_string(ensure_nl(header_line), skip_headers: false)

        overview_path
        |> File.stream!()
        |> Stream.drop(1)
        |> Stream.flat_map(fn line ->
          case CSV.parse_string(ensure_nl(line), skip_headers: false) do
            [fields] ->
              row = headers |> Enum.zip(fields) |> Map.new()

              case {row["report_id"], row["registrikood"], row["aruandeaasta"]} do
                {rid, code, ys} when is_binary(rid) and rid != "" and is_binary(code) ->
                  case Integer.parse(ys || "") do
                    {year, ""} -> [{rid, %{registry_code: code, year: year}}]
                    _ -> []
                  end

                _ ->
                  []
              end

            _ ->
              []
          end
        end)
        |> Enum.into(%{})
      end)

    IO.puts("fat index : #{map_size(m)} keys in #{Float.round(us / 1_000_000, 1)} s")
    m
  end

  defp ensure_nl(line) do
    case :binary.last(line) do
      ?\n -> line
      _ -> line <> "\n"
    end
  end

  defp print_heap(label, mem) do
    IO.puts(
      "#{label}   : #{div(mem[:total], 1024 * 1024)} MB total, " <>
        "#{div(mem[:binary], 1024 * 1024)} MB binary, " <>
        "#{div(mem[:processes], 1024 * 1024)} MB processes"
    )
  end
end
