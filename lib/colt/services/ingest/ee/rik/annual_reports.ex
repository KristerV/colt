defmodule Colt.Services.Ingest.Ee.Rik.AnnualReports do
  @moduledoc """
  Builds `Colt.Resources.AnnualReport` rows for the last three filed fiscal
  years from rik.ee data:

  1. From `aruannete_yldandmed.csv`, pick the latest report per
     (registry_code, year) by `esitatud_kpv`.
  2. From each `elemendid_YYYY.csv`, pick out Revenue (under non-liquidation
     `Kasumiaruanne skeem 1/2`) and average employees (under
     `Lisa: Tööjõukulud`). Liquidation-only reports are dropped.
  3. Upsert one `AnnualReport` per (company, year), then recompute growth on
     every affected company.
  """

  alias Colt.Resources.{AnnualReport, Company}
  alias Colt.Services.Ingest.Progress

  @overview_file "aruannete_yldandmed.csv"
  @revenue_tables MapSet.new(["Kasumiaruanne skeem 1", "Kasumiaruanne skeem 2"])
  @employee_table "Lisa: Tööjõukulud"

  def run do
    with {:ok, year_files} <- locate_year_files(),
         years <- year_files |> Enum.map(&elem(&1, 0)),
         {:ok, latest_by_report} <- index_latest_reports(years),
         {:ok, by_code} <- index_companies(),
         {:ok, %{count: count, affected: affected}} <-
           upsert_reports(year_files, latest_by_report, by_code),
         {:ok, _} <- recompute_growth(affected) do
      {:ok, %{processed: count, years: years, growth_recomputed: MapSet.size(affected)}}
    end
  end

  # ---- file discovery ----

  defp locate_year_files do
    dir = Application.fetch_env!(:colt, :rik_ee_cache_dir)

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
      |> Enum.take(3)
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
      |> Stream.map(&parse_overview_row(&1, headers))
      |> Stream.reject(&is_nil/1)
      |> Stream.filter(&MapSet.member?(years_set, &1.year))
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
    {:ok, Company.list_by_market!(:ee) |> Map.new(&{&1.registry_code, &1})}
  end

  # ---- read elemendid → upsert AnnualReports ----

  defp upsert_reports(year_files, latest_by_report, by_code) do
    Enum.reduce_while(year_files, {:ok, %{count: 0, affected: MapSet.new()}}, fn {year, path},
                                                                                 {:ok, acc} ->
      values_by_report = collect_values(path, latest_by_report)

      params_list =
        Enum.flat_map(values_by_report, fn {report_id, vals} ->
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
        end)

      params_list
      |> Stream.chunk_every(500)
      |> Enum.each(fn chunk ->
        Ash.bulk_create!(chunk, AnnualReport, :upsert,
          return_errors?: true,
          stop_on_error?: true
        )
      end)

      Progress.done("annual reports upserted (#{year})", length(params_list))

      affected =
        Enum.reduce(params_list, acc.affected, fn p, set -> MapSet.put(set, p.company_id) end)

      {:cont, {:ok, %{count: acc.count + length(params_list), affected: affected}}}
    end)
  end

  defp collect_values(path, latest_by_report) do
    [header_line] = path |> File.stream!() |> Enum.take(1)
    headers = parse_csv_line(header_line)

    label = "elemendid rows (#{Path.basename(path)})"

    path
    |> File.stream!()
    |> Stream.drop(1)
    |> Stream.map(&parse_element_row(&1, headers))
    |> Stream.reject(&is_nil/1)
    |> Stream.filter(&Map.has_key?(latest_by_report, &1.report_id))
    |> Progress.tick(label)
    |> Enum.reduce(%{}, fn row, acc ->
      classify(row, acc)
    end)
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

  defp classify(%{element: "Revenue", tabel: tabel, value: v, report_id: rid}, acc) do
    if MapSet.member?(@revenue_tables, tabel) do
      put_value(acc, rid, :revenue, parse_decimal(v))
    else
      acc
    end
  end

  defp classify(
         %{
           element: "AverageNumberOfEmployeesInFullTimeEquivalentUnits",
           tabel: @employee_table,
           value: v,
           report_id: rid
         },
         acc
       ) do
    put_value(acc, rid, :employees, parse_employee_count(v))
  end

  defp classify(_row, acc), do: acc

  defp put_value(acc, rid, key, value) do
    Map.update(acc, rid, %{revenue: nil, employees: nil} |> Map.put(key, value), fn vals ->
      Map.put(vals, key, value)
    end)
  end

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

  # Bulk recompute via a single SQL CTE — the per-company `:compute_growth`
  # Ash action stays the source of truth for individual recomputes (e.g. when
  # a single annual report changes outside this ingest). For the post-ingest
  # sweep we'd otherwise be doing one read + one update per company; SQL
  # collapses ~250k of those into one query.
  defp recompute_growth(_affected) do
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

  # ---- shared CSV helper (handles quoted fields) ----

  defp parse_csv_line(line) do
    line
    |> String.replace_prefix("﻿", "")
    |> String.trim_trailing("\n")
    |> String.trim_trailing("\r")
    |> do_parse_fields([], "", false)
  end

  defp do_parse_fields("", acc, current, _in_quote),
    do: Enum.reverse([current | acc])

  defp do_parse_fields(<<?", rest::binary>>, acc, current, in_quote),
    do: do_parse_fields(rest, acc, current, not in_quote)

  defp do_parse_fields(<<?;, rest::binary>>, acc, current, false),
    do: do_parse_fields(rest, [current | acc], "", false)

  defp do_parse_fields(<<c::utf8, rest::binary>>, acc, current, in_quote),
    do: do_parse_fields(rest, acc, current <> <<c::utf8>>, in_quote)
end
