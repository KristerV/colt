defmodule Colt.Services.Ingest.Lv.Ur.AnnualReports do
  @moduledoc """
  Builds `Colt.Resources.AnnualReport` rows for the last
  `:ingest_max_years` filed fiscal years from UR's open-data dumps:

  1. From `financial_statements.csv` (the statement-header file) we
     build `%{statement_id => %{regcode, year, employees}}` keeping only
     EUR-denominated statements rounded to ones, restricted to the
     configured year window, and keeping the most-recently-created
     statement per `(regcode, year)`.
  2. From the DB we build `%{regcode => company_id}` for `market: :lv`.
  3. We stream `income_statements.csv`, look up `statement_id` →
     `{regcode, year, employees}`, join `regcode → company_id`, and
     bulk-insert via raw SQL `unnest` + `ON CONFLICT DO NOTHING`.

  The pattern is identical to `Ee.Rik.AnnualReports` (same playbook in
  `docs/large-csv-ingest.md` — raw SQL, `unnest`, do-nothing on conflict)
  but the join is two-CSV instead of two-pass-of-one-CSV.
  """

  require Logger

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @financials_file "financial_statements.csv"
  @income_file "income_statements.csv"
  @insert_chunk 5_000

  def run do
    with {:ok, headers_idx} <- locate_files(),
         {:ok, years} <- target_years(),
         {:ok, by_statement} <- index_statements(headers_idx.financials, years),
         {:ok, by_code} <- index_companies(),
         {:ok, count} <- upsert_reports(headers_idx.income, by_statement, by_code) do
      {:ok, %{processed: count, years: years}}
    end
  end

  defp locate_files do
    dir = Application.fetch_env!(:colt, :ur_lv_cache_dir)
    financials = Path.join(dir, @financials_file)
    income = Path.join(dir, @income_file)

    cond do
      not File.exists?(financials) -> {:error, {:not_found, financials}}
      not File.exists?(income) -> {:error, {:not_found, income}}
      true -> {:ok, %{financials: financials, income: income}}
    end
  end

  # Pull the last N completed fiscal years. RIK's `ingest_max_years` is
  # reused — by config default that's 3. We compute `today.year - 1` as the
  # most-recent expected fully-filed year and walk backwards.
  defp target_years do
    max = Application.fetch_env!(:colt, :ingest_max_years)
    last_full = Date.utc_today().year - 1
    {:ok, MapSet.new((last_full - max + 1)..last_full)}
  end

  # ---- pass 1: index financial_statements.csv ----

  defp index_statements(path, years_set) do
    [header_line] = path |> File.stream!() |> Enum.take(1)
    headers = parse_header(header_line)

    cols =
      column_index(
        headers,
        ~w(id legal_entity_registration_number year employees currency rounded_to_nearest created_at)
      )

    by_pair =
      path
      |> raw_line_stream()
      |> Stream.drop(1)
      |> Progress.tick("financial_statements rows read")
      |> Stream.map(&parse_statement_row(&1, cols))
      |> Stream.reject(&is_nil/1)
      |> Stream.filter(&MapSet.member?(years_set, &1.year))
      |> Stream.filter(&Sample.included?(&1.registry_code))
      |> Enum.reduce(%{}, fn row, acc ->
        key = {row.registry_code, row.year}

        Map.update(acc, key, row, fn existing ->
          if row.created_at_sortable >= existing.created_at_sortable, do: row, else: existing
        end)
      end)

    by_statement =
      Map.new(by_pair, fn {{code, year}, row} ->
        {row.statement_id, %{registry_code: code, year: year, employees: row.employees}}
      end)

    Progress.done("statement index built", map_size(by_statement))
    {:ok, by_statement}
  end

  # Positional parse: `financial_statements.csv` has 12 unquoted columns
  # separated by `;`. We pre-resolve column positions from the header so
  # we don't pay header-map cost per row.
  defp parse_statement_row(line, cols) do
    fields = :binary.split(line, ";", [:global])

    with {:ok, id} <- at(fields, cols.id),
         {:ok, regcode} <- at(fields, cols.legal_entity_registration_number),
         {:ok, year_s} <- at(fields, cols.year),
         {:ok, currency} <- at(fields, cols.currency),
         {:ok, rounded} <- at(fields, cols.rounded_to_nearest),
         true <- String.trim(currency) == "EUR",
         true <- String.trim(rounded) == "ONES",
         {year, _} <- Integer.parse(year_s),
         emp <- at_int(fields, cols.employees),
         created <- at_or_empty(fields, cols.created_at) do
      %{
        statement_id: :binary.copy(String.trim(id)),
        registry_code: :binary.copy(String.trim(regcode)),
        year: year,
        employees: emp,
        created_at_sortable: created
      }
    else
      _ -> nil
    end
  end

  defp at(fields, idx) do
    case Enum.at(fields, idx) do
      nil -> :error
      "" -> :error
      v -> {:ok, v}
    end
  end

  defp at_or_empty(fields, idx), do: Enum.at(fields, idx) || ""

  defp at_int(fields, idx) do
    case Enum.at(fields, idx) do
      nil ->
        nil

      "" ->
        nil

      v ->
        case Integer.parse(String.trim(v)) do
          {n, _} -> n
          :error -> nil
        end
    end
  end

  defp parse_header(line) do
    line
    |> String.replace_prefix("﻿", "")
    |> String.trim_trailing("\n")
    |> String.trim_trailing("\r")
    |> String.split(";")
  end

  defp column_index(headers, names) do
    names
    |> Enum.map(fn name -> {String.to_atom(name), Enum.find_index(headers, &(&1 == name))} end)
    |> Map.new()
  end

  # ---- index existing companies (market: :lv) ----

  defp index_companies do
    companies =
      Company
      |> Ash.Query.for_read(:list_by_market, %{market: :lv})
      |> Ash.Query.select([:id, :registry_code])
      |> Ash.read!()

    Progress.done("LV companies indexed", length(companies))
    {:ok, Map.new(companies, &{&1.registry_code, &1})}
  end

  # ---- pass 2: stream income_statements.csv → upsert ----

  defp upsert_reports(path, by_statement, by_code) do
    [header_line] = path |> File.stream!() |> Enum.take(1)
    headers = parse_header(header_line)
    cols = column_index(headers, ~w(statement_id net_turnover))

    count =
      path
      |> raw_line_stream()
      |> Stream.drop(1)
      |> Progress.tick("income_statements rows read")
      |> Stream.filter(&relevant_statement?(&1, by_statement))
      |> Stream.map(&parse_income_row(&1, cols))
      |> Stream.reject(&is_nil/1)
      |> Stream.flat_map(&to_params(&1, by_statement, by_code))
      |> Stream.chunk_every(@insert_chunk)
      |> Enum.reduce(0, fn chunk, n ->
        bulk_insert_ignore(chunk)
        n + length(chunk)
      end)

    Progress.done("UR annual reports upserted", count)
    {:ok, count}
  end

  # Cheap-skip rows whose statement_id isn't in our pruned set. statement_id
  # is the first column of `income_statements.csv`; bailing here avoids
  # parsing the rest for ~99% of rows (the file has full history back to
  # 1996, we only keep the last `ingest_max_years` fiscal years).
  defp relevant_statement?(line, by_statement) do
    case :binary.split(line, ";") do
      [sid, _] -> Map.has_key?(by_statement, sid)
      _ -> false
    end
  end

  defp parse_income_row(line, cols) do
    fields = :binary.split(line, ";", [:global])

    with {:ok, sid} <- at(fields, cols.statement_id),
         {:ok, turnover} <- at(fields, cols.net_turnover) do
      %{
        statement_id: :binary.copy(String.trim(sid)),
        net_turnover: parse_decimal(turnover)
      }
    else
      _ -> nil
    end
  end

  defp parse_decimal(s) do
    case Decimal.parse(String.trim(s)) do
      {dec, _} -> dec
      :error -> nil
    end
  end

  defp to_params(%{statement_id: sid, net_turnover: turnover}, by_statement, by_code) do
    case {Map.get(by_statement, sid), turnover} do
      {nil, _} ->
        []

      {_meta, nil} ->
        []

      {meta, rev} ->
        case Map.get(by_code, meta.registry_code) do
          nil ->
            []

          %{id: company_id} ->
            [
              %{
                company_id: company_id,
                year: meta.year,
                revenue_eur: rev,
                employees: meta.employees,
                source: :ur
              }
            ]
        end
    end
  end

  # Raw multi-row INSERT … ON CONFLICT DO NOTHING. Same pattern + rationale
  # as `Ee.Rik.AnnualReports.bulk_insert_ignore/1`. UR financial statements
  # are immutable once filed (the (regcode, year) pair latches), so DO
  # NOTHING is the correct semantic for repeated runs.
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

  # ---- raw chunked line reader (see docs/large-csv-ingest.md §1.4) ----

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
            case :binary.split(buffer <> chunk, "\n", [:global]) do
              [only] ->
                {[], %{state | buffer: only}}

              many ->
                [partial | rev_lines] = Enum.reverse(many)
                lines = Enum.reduce(rev_lines, [], &[&1 <> "\n" | &2])
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
end
