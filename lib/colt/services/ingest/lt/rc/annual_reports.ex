NimbleCSV.define(Colt.Services.Ingest.Lt.Rc.AnnualReports.CommaCSV,
  separator: ",",
  escape: "\""
)

NimbleCSV.define(Colt.Services.Ingest.Lt.Rc.AnnualReports.PipeCSV,
  separator: "|",
  escape: "\""
)

defmodule Colt.Services.Ingest.Lt.Rc.AnnualReports do
  @moduledoc """
  Builds `Colt.Resources.AnnualReport` rows from the per-fiscal-year
  Registrų centras profit/loss dumps (`plna_YYYY.csv`).

  Per `docs/countries/lt.md`:

  - `pardavimo_pajamos` → `revenue_eur` (EUR, integer-encoded).
  - `employees` stays `nil` (RC has no headcount; comes from Sodra).
  - Multiple filings per (company, fiscal_year) can exist (amendments)
    — keep the latest by `reg_date`.
  - The fiscal year is the year of `laikotarpis_iki` (closing date),
    not the report's submission year.

  Hot path mirrors EE/RIK: raw multi-row `INSERT … ON CONFLICT DO
  NOTHING` via `unnest()`. Sodra's `HeadcountImport` later DOES the
  per-row UPDATE for headcount.
  """

  require Logger

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Lt.Rc.AnnualReports.{CommaCSV, PipeCSV}
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @batch 500

  def run do
    with {:ok, year_files} <- locate_year_files(),
         {:ok, by_code} <- index_companies(),
         {:ok, count} <- import_each(year_files, by_code) do
      years = year_files |> Enum.map(&elem(&1, 0))
      {:ok, %{processed: count, years: years}}
    end
  end

  defp locate_year_files do
    dir = Application.fetch_env!(:colt, :rc_lt_cache_dir)

    files =
      dir
      |> File.ls!()
      |> Enum.flat_map(fn name ->
        case Regex.run(~r/^plna_(\d{4})\.csv$/, name) do
          [_, year] -> [{String.to_integer(year), Path.join(dir, name)}]
          _ -> []
        end
      end)
      |> Enum.sort_by(&elem(&1, 0))

    case files do
      [] -> {:error, :no_plna_files}
      list -> {:ok, list}
    end
  end

  defp index_companies do
    companies =
      Company
      |> Ash.Query.for_read(:list_by_market, %{market: :lt})
      |> Ash.Query.select([:id, :registry_code])
      |> Ash.read!()

    {:ok, Map.new(companies, &{&1.registry_code, &1.id})}
  end

  defp import_each(year_files, by_code) do
    total =
      Enum.reduce(year_files, 0, fn {year, path}, acc ->
        n =
          path
          |> stream_rows()
          |> Progress.tick("PLNA rows (#{year})")
          |> Stream.filter(&Sample.included?(&1.registry_code))
          |> dedupe_latest_per_pair()
          |> Stream.flat_map(&to_params(&1, by_code))
          |> Stream.chunk_every(@batch)
          |> Enum.reduce(0, fn chunk, written ->
            bulk_insert_ignore(chunk)
            written + length(chunk)
          end)

        Progress.done("LT annual reports upserted (#{year})", n)
        acc + n
      end)

    {:ok, total}
  end

  # PLNA files for a single fiscal year typically have ~120k rows. We
  # parse the whole file with NimbleCSV.parse_stream/1 (which uses the
  # raw file driver internally — see large-csv-ingest.md §4) and then
  # collapse amendments by keeping the row with the latest `reg_date`
  # per (registry_code, fiscal_year). Holding ~120k tuples in memory is
  # fine; we don't try to chunk_by because rows aren't sorted by code.
  defp stream_rows(path) do
    parser = detect_parser(path)

    path
    |> File.stream!([:raw, :read_ahead, :binary])
    |> parser.parse_stream(skip_headers: true)
    |> Stream.map(&parse_row/1)
    |> Stream.reject(&is_nil/1)
  end

  # RC switched the PLNA file separator from `,` (2015→2022) to `|`
  # (2023→). Sniff the header to pick the right NimbleCSV parser per
  # file so we don't have to re-version this module each year.
  defp detect_parser(path) do
    head =
      File.open!(path, [:read, :raw, :binary], fn fd ->
        case :file.read(fd, 512) do
          {:ok, data} -> data
          _ -> ""
        end
      end)

    case String.split(head, ~r/\r?\n/, parts: 2) do
      [first | _] -> if String.contains?(first, "|"), do: PipeCSV, else: CommaCSV
      _ -> CommaCSV
    end
  end

  # Header layout (verified 2026-05-28):
  # 0  obj_kodas
  # 1  obj_pav
  # 2  form_kodas
  # 3  form_pav
  # 4  stat_statusas
  # 5  stat_pav
  # 6  template_id
  # 7  template_name
  # 8  standard_id
  # 9  standard_name
  # 10 laikotarpis_nuo
  # 11 laikotarpis_iki
  # 12 reg_date
  # 13 pelnas_pries_apmokestinima
  # 14 grynasis_pelnas
  # 15 pardavimo_pajamos
  # 16 formavimo_data
  defp parse_row([code, _, _, _, _, _, _, _, _, _, _, period_to, reg_date, _, _, revenue | _]) do
    with code when code not in [nil, ""] <- String.trim(code),
         <<year_bin::binary-size(4), _::binary>> <- to_string(period_to),
         {year, ""} <- Integer.parse(year_bin) do
      %{
        registry_code: :binary.copy(code),
        year: year,
        revenue: parse_decimal(revenue),
        reg_sortable: parse_iso_date(reg_date)
      }
    else
      _ -> nil
    end
  end

  defp parse_row(_), do: nil

  # Multiple PLNA rows can exist for the same (company, fiscal_year)
  # when a company amends a filing. Keep the latest by `reg_date`.
  defp dedupe_latest_per_pair(stream) do
    Stream.transform(
      stream,
      fn -> %{} end,
      fn row, acc ->
        key = {row.registry_code, row.year}

        case Map.get(acc, key) do
          nil ->
            {[], Map.put(acc, key, row)}

          existing ->
            if row.reg_sortable >= existing.reg_sortable do
              {[], Map.put(acc, key, row)}
            else
              {[], acc}
            end
        end
      end,
      fn acc -> {Map.values(acc), acc} end,
      fn _ -> :ok end
    )
  end

  defp to_params(row, by_code) do
    case Map.get(by_code, row.registry_code) do
      nil -> []
      company_id -> [%{company_id: company_id, year: row.year, revenue: row.revenue}]
    end
  end

  defp bulk_insert_ignore([]), do: 0

  defp bulk_insert_ignore(rows) do
    count = length(rows)
    now = DateTime.utc_now()

    ids = Enum.map(rows, fn _ -> Ecto.UUID.bingenerate() end)
    company_ids = Enum.map(rows, &Ecto.UUID.dump!(&1.company_id))
    years = Enum.map(rows, & &1.year)
    revenues = Enum.map(rows, & &1.revenue)
    employees = List.duplicate(nil, count)
    sources = List.duplicate("rc", count)
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

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(s) do
    case Decimal.parse(s) do
      {dec, _} -> dec
      :error -> nil
    end
  end

  # ISO date "YYYY-MM-DD" → integer for cheap lex compare. Missing /
  # malformed dates sort as oldest.
  defp parse_iso_date(nil), do: 0
  defp parse_iso_date(""), do: 0

  defp parse_iso_date(s) do
    case String.split(s, "-") do
      [y, m, d] ->
        case {Integer.parse(y), Integer.parse(m), Integer.parse(d)} do
          {{yi, _}, {mi, _}, {di, _}} -> yi * 10_000 + mi * 100 + di
          _ -> 0
        end

      _ ->
        0
    end
  end
end
