NimbleCSV.define(Colt.Services.Ingest.Ee.Rik.AnnualReports.CSV,
  separator: ";",
  escape: "\""
)

defmodule Colt.Services.Ingest.Ee.Rik.AnnualReports do
  @moduledoc """
  Builds `Colt.Resources.AnnualReport` rows for the last three filed fiscal
  years from rik.ee data:

  1. From `aruannete_yldandmed.csv`, pick the latest report per
     (registry_code, year) by `esitatud_kpv`.
  2. From each `elemendid_YYYY.csv`, pick out Revenue (under non-liquidation
     `Kasumiaruanne skeem 1/2`) and average employees (under
     `Lisa: Tööjõukulud`). Liquidation-only reports are dropped.
  3. Upsert one `AnnualReport` per (company, year), then recompute growth in
     a single SQL pass across all companies that have any reports.
  """

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Ee.Rik.AnnualReports.CSV
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @overview_file "aruannete_yldandmed.csv"
  @revenue_tables MapSet.new(["Kasumiaruanne skeem 1", "Kasumiaruanne skeem 2"])
  @employee_table "Lisa: Tööjõukulud"

  def run do
    with {:ok, year_files} <- locate_year_files(),
         years <- year_files |> Enum.map(&elem(&1, 0)),
         {:ok, latest_by_report} <- index_latest_reports(years),
         {:ok, by_code} <- index_companies(),
         {:ok, count} <- upsert_reports(year_files, latest_by_report, by_code),
         {:ok, recomputed} <- recompute_growth() do
      {:ok, %{processed: count, years: years, growth_recomputed: recomputed}}
    end
  end

  # ---- file discovery ----

  defp locate_year_files do
    dir = Application.fetch_env!(:colt, :rik_ee_cache_dir)
    max_years = Application.fetch_env!(:colt, :ingest_max_years)

    files =
      dir
      |> File.ls!()
      |> Enum.flat_map(fn name ->
        case Regex.run(~r/^elemendid_(\d{4})\.csv$/, name) do
          [_, year] -> [{String.to_integer(year), Path.join(dir, name)}]
          _ -> []
        end
      end)
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> Enum.take(max_years)
      |> Enum.sort_by(&elem(&1, 0))

    case files do
      [] -> {:error, :no_elemendid_files}
      list -> {:ok, list}
    end
  end

  # ---- index aruannete_yldandmed → latest report per (code, year) ----

  defp index_latest_reports(years) do
    dir = Application.fetch_env!(:colt, :rik_ee_cache_dir)
    path = Path.join(dir, @overview_file)
    years_set = MapSet.new(years)

    [header_line] = path |> File.stream!() |> Enum.take(1)
    headers = parse_csv_line(header_line)

    by_pair =
      path
      |> File.stream!()
      |> Stream.drop(1)
      |> Progress.tick("aruannete rows read")
      |> Stream.map(&parse_overview_row(&1, headers))
      |> Stream.reject(&is_nil/1)
      |> Stream.filter(&MapSet.member?(years_set, &1.year))
      |> Stream.filter(&Sample.included?(&1.registry_code))
      |> Enum.reduce(%{}, fn row, acc ->
        key = {row.registry_code, row.year}

        Map.update(acc, key, row, fn existing ->
          if row.esitatud_sortable >= existing.esitatud_sortable, do: row, else: existing
        end)
      end)

    by_report =
      Map.new(by_pair, fn {{code, year}, row} ->
        {row.report_id, %{registry_code: code, year: year}}
      end)

    {:ok, by_report}
  end

  defp parse_overview_row(line, headers) do
    fields = parse_csv_line(line)
    map = headers |> Enum.zip(fields) |> Map.new()

    with report_id when report_id not in [nil, ""] <- map["report_id"],
         code when code not in [nil, ""] <- map["registrikood"],
         year_str when year_str not in [nil, ""] <- map["aruandeaasta"],
         {year, ""} <- Integer.parse(year_str) do
      # Copy these binaries: they're sub-binaries of the NimbleCSV-parsed
      # line. Without the copy they keep the whole line alive in the heap,
      # which on a 2GB Fly box overflows during the 1.5M-row aruannete read.
      %{
        report_id: :binary.copy(report_id),
        registry_code: :binary.copy(code),
        year: year,
        esitatud_sortable: parse_eu_date(map["esitatud_kpv"])
      }
    else
      _ -> nil
    end
  end

  defp parse_eu_date(nil), do: 0
  defp parse_eu_date(""), do: 0

  defp parse_eu_date(s) do
    case String.split(s, ".") do
      [d, m, y] -> String.to_integer(y <> m <> d)
      _ -> 0
    end
  end

  # ---- index existing companies ----

  defp index_companies do
    companies =
      Company
      |> Ash.Query.for_read(:list_by_market, %{market: :ee})
      |> Ash.Query.select([:id, :registry_code])
      |> Ash.read!()

    {:ok, Map.new(companies, &{&1.registry_code, &1})}
  end

  # ---- read elemendid → upsert AnnualReports ----

  defp upsert_reports(year_files, latest_by_report, by_code) do
    total =
      Enum.reduce(year_files, 0, fn {year, path}, count ->
        last_ref = :erlang.make_ref()
        Process.put({:last_chunk_end, last_ref}, System.monotonic_time(:microsecond))
        Process.put({:last_proc_snapshot, last_ref}, proc_snapshot())

        n =
          path
          |> stream_reports(latest_by_report)
          |> Stream.flat_map(fn report ->
            t = System.monotonic_time(:microsecond)
            params = to_params(report, year, latest_by_report, by_code)
            tick_us(:t_params, System.monotonic_time(:microsecond) - t)
            params
          end)
          |> tap_each(:t_chunk_every)
          |> Stream.chunk_every(500)
          |> Stream.with_index(1)
          |> Enum.reduce(0, fn {chunk, idx}, written ->
            chunk_filled = System.monotonic_time(:microsecond)
            produce_us = chunk_filled - Process.get({:last_chunk_end, last_ref})

            snap_before = Process.get({:last_proc_snapshot, last_ref})
            snap_after = proc_snapshot()

            {db_us, _} = :timer.tc(fn -> bulk_insert_ignore(chunk) end)

            now = System.monotonic_time(:microsecond)
            Process.put({:last_chunk_end, last_ref}, now)
            Process.put({:last_proc_snapshot, last_ref}, proc_snapshot())

            require Logger

            Logger.info(
              "chunk #{idx}/#{year}: #{length(chunk)} rows | " <>
                "produce #{div(produce_us, 1000)}ms " <>
                "(filter=#{pop_ms(:t_filter)} parse=#{pop_ms(:t_parse)} " <>
                "fold=#{pop_ms(:t_fold)} params=#{pop_ms(:t_params)} " <>
                "reject=#{pop_ms(:t_reject)} chunk_by=#{pop_ms(:t_chunk_by)} " <>
                "chunk_every=#{pop_ms(:t_chunk_every)}) | " <>
                "gc #{snap_after.gc_count - snap_before.gc_count} colls, " <>
                "#{div((snap_after.gc_words - snap_before.gc_words) * 8, 1024 * 1024)} MB reclaimed | " <>
                "reds #{div(snap_after.reductions - snap_before.reductions, 1_000_000)} M | " <>
                "heap #{div(snap_after.total_heap * 8, 1024 * 1024)} MB " <>
                "(Δ#{div((snap_after.total_heap - snap_before.total_heap) * 8, 1024 * 1024)} MB) | " <>
                "bin #{div(snap_after.binary, 1024 * 1024)} MB | " <>
                "msgq #{snap_after.msg_queue} | " <>
                "db #{div(db_us, 1000)}ms"
            )

            written + length(chunk)
          end)

        Progress.done("annual reports upserted (#{year})", n)
        count + n
      end)

    {:ok, total}
  end

  # Snapshot of process state useful for diagnosing where time goes between
  # chunks: GC pressure, work done (reductions), heap pressure, retained
  # binary heap, mailbox backlog.
  defp proc_snapshot do
    {gc_count, gc_words, _} = :erlang.statistics(:garbage_collection)
    {:reductions, reds} = :erlang.process_info(self(), :reductions)
    {:total_heap_size, heap} = :erlang.process_info(self(), :total_heap_size)
    {:message_queue_len, msgq} = :erlang.process_info(self(), :message_queue_len)
    mem = :erlang.memory()

    %{
      gc_count: gc_count,
      gc_words: gc_words,
      reductions: reds,
      total_heap: heap,
      binary: Keyword.get(mem, :binary, 0),
      msg_queue: msgq
    }
  end

  # Raw multi-row INSERT … ON CONFLICT DO NOTHING. Bypasses Ash's per-row
  # changeset pipeline (validations, identity resolution, action lifecycle)
  # which dominated wall-clock time in the stage-4 hot path — roughly
  # 500-1000× slower per row than the underlying SQL. RIK annual reports
  # never get retroactively updated, so DO NOTHING is the correct semantic
  # for repeated runs.
  defp bulk_insert_ignore([]), do: 0

  defp bulk_insert_ignore(rows) do
    count = length(rows)
    now = DateTime.utc_now()

    ids = Enum.map(rows, fn _ -> Ecto.UUID.bingenerate() end)
    company_ids = Enum.map(rows, &Ecto.UUID.dump!(&1.company_id))
    years = Enum.map(rows, & &1.year)
    revenues = Enum.map(rows, & &1.revenue_eur)
    employees = Enum.map(rows, & &1.employees)
    sources = Enum.map(rows, &Atom.to_string(&1.source))
    timestamps = List.duplicate(now, count)

    sql = """
    INSERT INTO annual_reports
      (id, company_id, year, revenue_eur, employees, source, inserted_at, updated_at)
    SELECT * FROM unnest(
      $1::uuid[],
      $2::uuid[],
      $3::int[],
      $4::numeric[],
      $5::int[],
      $6::text[],
      $7::timestamptz[],
      $8::timestamptz[]
    )
    ON CONFLICT (company_id, year) DO NOTHING
    """

    {:ok, %{num_rows: inserted}} =
      Ecto.Adapters.SQL.query(
        Colt.Repo,
        sql,
        [ids, company_ids, years, revenues, employees, sources, timestamps, timestamps]
      )

    inserted
  end

  defp to_params({report_id, vals}, year, latest_by_report, by_code) do
    ref = Map.fetch!(latest_by_report, report_id)
    company = Map.get(by_code, ref.registry_code)

    cond do
      is_nil(company) ->
        []

      is_nil(vals.revenue) ->
        []

      true ->
        [
          %{
            company_id: company.id,
            year: year,
            revenue_eur: vals.revenue,
            employees: vals.employees,
            source: :rik
          }
        ]
    end
  end

  # Streams `{report_id, %{revenue, employees}}` tuples. elemendid CSVs are
  # sorted by report_id, so we group contiguous rows and fold each group
  # in isolation — no global accumulator, so GC stays cheap for the whole
  # 3.7M-row file.
  def stream_reports(path, latest_by_report) do
    label = "elemendid rows (#{Path.basename(path)})"

    path
    |> raw_line_stream()
    |> Stream.drop(1)
    |> Progress.tick(label)
    |> Stream.filter(fn line ->
      t = System.monotonic_time(:microsecond)
      ok? = relevant_report?(line, latest_by_report)
      tick_us(:t_filter, System.monotonic_time(:microsecond) - t)
      ok?
    end)
    |> Stream.map(fn line ->
      t = System.monotonic_time(:microsecond)
      row = parse_element_row(line)
      tick_us(:t_parse, System.monotonic_time(:microsecond) - t)
      row
    end)
    |> Stream.reject(fn row ->
      t = System.monotonic_time(:microsecond)
      nil? = is_nil(row)
      tick_us(:t_reject, System.monotonic_time(:microsecond) - t)
      nil?
    end)
    |> Stream.chunk_by(fn row ->
      t = System.monotonic_time(:microsecond)
      key = row.report_id
      tick_us(:t_chunk_by, System.monotonic_time(:microsecond) - t)
      key
    end)
    |> Stream.map(fn group ->
      t = System.monotonic_time(:microsecond)
      out = fold_group(group)
      tick_us(:t_fold, System.monotonic_time(:microsecond) - t)
      out
    end)
  end

  # Timing tap that measures time spent between successive emits at a point
  # in the pipeline. Useful for finding stages whose work isn't a function
  # we can wrap directly (e.g., Stream.chunk_every's list construction).
  defp tap_each(stream, key) do
    Stream.transform(
      stream,
      fn -> nil end,
      fn x, _ ->
        t = System.monotonic_time(:microsecond)
        tick_us(key, t - (Process.get({:last_tap, key}) || t))
        Process.put({:last_tap, key}, t)
        {[x], nil}
      end,
      fn _ -> :ok end
    )
  end

  # Bypasses Erlang's file_io_server. Each `:file.read/2` is a direct BIF
  # call into the file driver — no Port message round-trip, no scheduler
  # context switch per line. Reads in 256 KB chunks and emits all complete
  # lines from each chunk in a single Stream.resource step. The final
  # partial line stays in the buffer until the next read or EOF.
  defp raw_line_stream(path) do
    Stream.resource(
      fn ->
        {:ok, fd} =
          :file.open(path, [:read, :raw, :binary, {:read_ahead, 256 * 1024}])

        %{fd: fd, buffer: ""}
      end,
      fn %{fd: fd, buffer: buffer} = state ->
        case :file.read(fd, 256 * 1024) do
          {:ok, chunk} ->
            data = buffer <> chunk

            case :binary.split(data, "\n", [:global]) do
              [only] ->
                {[], %{state | buffer: only}}

              many ->
                [partial | rev_lines] = Enum.reverse(many)
                lines = rev_lines |> Enum.reverse() |> Enum.map(&(&1 <> "\n"))
                {lines, %{state | buffer: partial}}
            end

          :eof when byte_size(buffer) == 0 ->
            {:halt, state}

          :eof ->
            {[buffer], %{state | buffer: ""}}
        end
      end,
      fn %{fd: fd} -> :file.close(fd) end
    )
  end

  defp tick_us(key, us), do: Process.put(key, (Process.get(key) || 0) + us)

  defp pop_ms(key) do
    us = Process.get(key) || 0
    Process.put(key, 0)
    div(us, 1000)
  end

  @doc false
  # Eager variant for the bench harness. Don't use in the ingest hot path.
  def collect_values(path, latest_by_report) do
    path
    |> stream_reports(latest_by_report)
    |> Enum.into(%{})
  end

  defp fold_group([%{report_id: rid} | _] = rows) do
    vals = Enum.reduce(rows, %{revenue: nil, employees: nil}, &classify_row/2)
    {rid, vals}
  end

  # Cheap-skip rows whose report_id isn't in our latest-per-(code,year) set.
  # report_id is the first `;`-separated field; checking it avoids parsing the
  # remaining four columns for ~93% of rows in prod (more in dev).
  defp relevant_report?(line, latest_by_report) do
    case :binary.split(line, ";") do
      [rid, _rest] -> Map.has_key?(latest_by_report, rid)
      _ -> false
    end
  end

  # elemendid CSV format is rigid: 5 fields per row, semicolon-separated,
  # column 1 unquoted (report_id integer), columns 2-5 double-quoted strings.
  # Verified: no ;-fields outside quotes anywhere in elemendid_2023.csv.
  # Bypassing NimbleCSV here for a ~10× speedup over header-based map lookup.
  defp parse_element_row(line) do
    case :binary.split(line, ";", [:global]) do
      [<<>>, _, _, _, _] ->
        nil

      [report_id, tabel, _label, element, value_nl] ->
        # Copy each field: with read_ahead enabled on the source stream, the
        # line is a sub-binary of a 256KB buffer, and every sub-binary we
        # carry forward keeps that buffer pinned. Without copy, chunk_by +
        # chunk_every retain ~100MB of read buffers and GC tanks parse 60×.
        %{
          report_id: :binary.copy(report_id),
          tabel: :binary.copy(strip_quotes(tabel)),
          element: :binary.copy(strip_quotes(element)),
          value: :binary.copy(strip_quotes(trim_newline(value_nl)))
        }

      _ ->
        nil
    end
  end

  defp strip_quotes(<<?", rest::binary>>) when byte_size(rest) >= 1 do
    :binary.part(rest, 0, byte_size(rest) - 1)
  end

  defp strip_quotes(s), do: s

  defp trim_newline(bin) do
    case :binary.last(bin) do
      ?\n ->
        size = byte_size(bin) - 1

        case :binary.at(bin, size - 1) do
          ?\r -> :binary.part(bin, 0, size - 1)
          _ -> :binary.part(bin, 0, size)
        end

      _ ->
        bin
    end
  end

  defp classify_row(%{element: "Revenue", tabel: tabel, value: v}, vals) do
    if MapSet.member?(@revenue_tables, tabel) do
      %{vals | revenue: parse_decimal(v)}
    else
      vals
    end
  end

  defp classify_row(
         %{
           element: "AverageNumberOfEmployeesInFullTimeEquivalentUnits",
           tabel: @employee_table,
           value: v
         },
         vals
       ) do
    %{vals | employees: parse_employee_count(v)}
  end

  defp classify_row(_row, vals), do: vals

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(s) do
    case Decimal.parse(s) do
      {dec, _} -> dec
      :error -> nil
    end
  end

  defp parse_employee_count(nil), do: nil
  defp parse_employee_count(""), do: nil

  defp parse_employee_count(s) do
    case Float.parse(s) do
      {f, _} -> trunc(f)
      :error -> nil
    end
  end

  # ---- compute growth ----

  # Single-query recompute. Buckets per spec §3.1.
  defp recompute_growth do
    sql = """
    WITH ranked AS (
      SELECT
        company_id,
        revenue_eur,
        employees,
        year,
        ROW_NUMBER() OVER (PARTITION BY company_id ORDER BY year DESC) AS rn
      FROM annual_reports
    ),
    agg AS (
      SELECT
        company_id,
        MAX(revenue_eur) FILTER (WHERE rn = 1) AS revenue_latest,
        MAX(employees)   FILTER (WHERE rn = 1) AS employees_latest,
        MAX(revenue_eur) FILTER (WHERE rn = 2) AS revenue_prev
      FROM ranked
      GROUP BY company_id
    ),
    growth AS (
      SELECT
        company_id,
        revenue_latest,
        employees_latest,
        CASE
          WHEN revenue_prev IS NULL OR revenue_latest IS NULL THEN NULL
          WHEN revenue_prev <= 0 AND revenue_latest > 0 THEN 'growing_10x'
          WHEN revenue_prev <= 0 THEN 'stagnant'
          WHEN revenue_latest < revenue_prev THEN 'declining'
          WHEN (revenue_latest - revenue_prev) / revenue_prev <= 0.05 THEN 'stagnant'
          WHEN (revenue_latest - revenue_prev) / revenue_prev <= 1.0  THEN 'slow'
          WHEN (revenue_latest - revenue_prev) / revenue_prev <= 9.0  THEN 'growing_2x'
          ELSE 'growing_10x'
        END AS bucket
      FROM agg
    )
    UPDATE companies c
    SET
      revenue_latest = g.revenue_latest,
      employees_latest = g.employees_latest,
      revenue_growth_bucket = g.bucket
    FROM growth g
    WHERE c.id = g.company_id
    """

    {:ok, %{num_rows: n}} = Ecto.Adapters.SQL.query(Colt.Repo, sql, [])
    Progress.done("growth recomputed", n)
    {:ok, n}
  end

  # ---- shared CSV helper (NimbleCSV-backed) ----

  # NimbleCSV needs a newline-terminated string and skips a header by default.
  # We pass `skip_headers: false` because we hand it single lines.
  defp parse_csv_line(line) do
    line
    |> strip_bom()
    |> ensure_trailing_newline()
    |> CSV.parse_string(skip_headers: false)
    |> case do
      [fields] -> fields
      [] -> []
    end
  end

  defp strip_bom(<<"﻿", rest::binary>>), do: rest
  defp strip_bom(line), do: line

  defp ensure_trailing_newline(line) do
    case :binary.last(line) do
      ?\n -> line
      _ -> line <> "\n"
    end
  end
end
