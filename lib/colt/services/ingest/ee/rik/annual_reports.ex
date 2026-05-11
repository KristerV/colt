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
      %{
        report_id: report_id,
        registry_code: code,
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

        n =
          path
          |> stream_reports(latest_by_report)
          |> Stream.flat_map(fn report ->
            t = System.monotonic_time(:microsecond)
            params = to_params(report, year, latest_by_report, by_code)
            tick_us(:t_params, System.monotonic_time(:microsecond) - t)
            params
          end)
          |> Stream.chunk_every(500)
          |> Stream.with_index(1)
          |> Enum.reduce(0, fn {chunk, idx}, written ->
            chunk_filled = System.monotonic_time(:microsecond)
            produce_us = chunk_filled - Process.get({:last_chunk_end, last_ref})

            {db_us, _} = :timer.tc(fn -> bulk_insert_ignore(chunk) end)

            now = System.monotonic_time(:microsecond)
            Process.put({:last_chunk_end, last_ref}, now)

            require Logger

            Logger.info(
              "chunk #{idx}/#{year}: #{length(chunk)} rows | " <>
                "produce #{div(produce_us, 1000)}ms " <>
                "(filter=#{pop_ms(:t_filter)} parse=#{pop_ms(:t_parse)} " <>
                "fold=#{pop_ms(:t_fold)} params=#{pop_ms(:t_params)}) | " <>
                "db #{div(db_us, 1000)}ms"
            )

            written + length(chunk)
          end)

        Progress.done("annual reports upserted (#{year})", n)
        count + n
      end)

    {:ok, total}
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
    [header_line] = path |> File.stream!() |> Enum.take(1)
    headers = parse_csv_line(header_line)

    label = "elemendid rows (#{Path.basename(path)})"

    path
    |> File.stream!()
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
      row = parse_element_row(line, headers)
      tick_us(:t_parse, System.monotonic_time(:microsecond) - t)
      row
    end)
    |> Stream.reject(&is_nil/1)
    |> Stream.chunk_by(& &1.report_id)
    |> Stream.map(fn group ->
      t = System.monotonic_time(:microsecond)
      out = fold_group(group)
      tick_us(:t_fold, System.monotonic_time(:microsecond) - t)
      out
    end)
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

  defp parse_element_row(line, headers) do
    fields = parse_csv_line(line)
    map = headers |> Enum.zip(fields) |> Map.new()

    case map["report_id"] do
      nil ->
        nil

      "" ->
        nil

      report_id ->
        %{
          report_id: report_id,
          tabel: map["tabel"],
          element: map["elemendi_nimetus"],
          value: map["vaartus"]
        }
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
