NimbleCSV.define(Colt.Services.Ingest.Lv.Ur.IndustryCodes.CSV,
  separator: ",",
  escape: "\""
)

defmodule Colt.Services.Ingest.Lv.Ur.IndustryCodes do
  @moduledoc """
  Fills `companies.industry_code` for `market: :lv` from VID's three-year
  paid-tax dump (`vid_taxes_3y.csv`).

  Latvia's company register publishes no NACE — but VID's tax dump carries
  `Pamatdarbibas_NACE_kods` (principal activity, 4-digit) keyed by
  `Registracijas_kods`, which joins straight to `register.csv`'s `regcode`.
  One row per company per tax year; we keep each company's newest row.

  ## Revision handling

  The **tax year is the classifier version**, so Latvia is Estonia's case
  (revision known) rather than Lithuania's (revision guessed) — see
  `docs/countries/industry-codes.md`. Latvia applied NACE Rev. 2.1 from
  tax year 2024; earlier years are Rev. 2. Verified by partitioning the
  file against `priv/nace/nace_rev2_to_rev21.csv` (playbook Rule 4):

      year   rev2-only   rev21-only     both
      2022       48000            0    86586
      2023       50221            0    91006
      2024         429        41448    76580

  2022/23 hold **zero** Rev-2.1-only codes, confirming they are Rev. 2. But
  2024 is *not* purely Rev. 2.1 — 429 rows still carry a class Rev. 2.1
  deleted. So the year alone is not sufficient: a Rev-2-only code is treated
  as Rev. 2 whatever year it was filed under.

  Knowing the revision is what makes the 23 reused codes safe. On a Rev-2.1
  row a collision code is unambiguous and passes through untouched; only on
  a Rev-2 row is it genuinely undecidable, and there it drops to `nil`
  rather than mislabel the company. `nil` is written **through**, not
  skipped, so a stale code can never survive a re-run.

  Translation happens here, at import — never as a backfill. VID keeps
  serving the old codes, so a backfill would be undone by the next ingest.
  """

  require Logger

  alias Colt.Filters.NaceMigration
  alias Colt.Repo
  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Lv.Ur.IndustryCodes.CSV
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @filename "vid_taxes_3y.csv"
  @batch 5_000

  # First tax year filed under NACE Rev. 2.1 (the EU renumbered on 2025-01-01
  # and Latvia applied it to the 2024 filings).
  @rev21_from_year 2024

  def run do
    with {:ok, path} <- locate_file(),
         {:ok, by_code} <- index_companies(),
         {:ok, newest} <- newest_code_per_company(path),
         {:ok, stats} <- upsert_industry(newest, by_code) do
      Logger.info(
        "LV NACE: #{stats.assigned} assigned, #{stats.dropped} dropped (ambiguous), " <>
          "#{stats.unmatched} unmatched"
      )

      {:ok, stats}
    end
  end

  defp locate_file do
    dir = Application.fetch_env!(:colt, :ur_lv_cache_dir)
    path = Path.join(dir, @filename)

    if File.exists?(path), do: {:ok, path}, else: {:error, {:not_found, path}}
  end

  defp index_companies do
    companies =
      Company
      |> Ash.Query.for_read(:list_by_market, %{market: :lv})
      |> Ash.Query.select([:id, :registry_code])
      |> Ash.read!()

    Progress.done("LV companies indexed", length(companies))
    {:ok, Map.new(companies, &{&1.registry_code, &1.id})}
  end

  # `vid_taxes_3y.csv` is UTF-8-with-BOM, comma-separated and fully quoted —
  # and legal names contain commas, so this must be a real CSV parse rather
  # than a `:binary.split/3` on ",". NimbleCSV's `parse_stream` opens the
  # file `:raw` internally (docs/large-csv-ingest.md §1.4).
  defp newest_code_per_company(path) do
    newest =
      path
      |> File.stream!()
      |> CSV.parse_stream()
      |> Progress.tick("VID tax rows read")
      |> Stream.map(&parse_row/1)
      |> Stream.reject(&is_nil/1)
      |> Stream.filter(&Sample.included?(&1.registry_code))
      |> Enum.reduce(%{}, fn row, acc ->
        Map.update(acc, row.registry_code, row, fn existing ->
          if row.year >= existing.year, do: row, else: existing
        end)
      end)

    Progress.done("VID companies with a NACE code", map_size(newest))
    {:ok, newest}
  end

  # Positional: Registracijas_kods, Nosaukums, Taksacijas_gads,
  # Uznemejdarbibas_forma, Pamatdarbibas_NACE_kods, …
  # The NACE column is `"?"` for companies that declared none, and is
  # space-padded (`"9531  "`).
  defp parse_row([reg, _name, year, _form, nace | _]) do
    code = String.trim(nace)

    with true <- String.length(code) == 4,
         {y, _} <- Integer.parse(String.trim(year)) do
      %{
        registry_code: :binary.copy(String.trim(reg)),
        year: y,
        code: :binary.copy(code)
      }
    else
      _ -> nil
    end
  end

  defp parse_row(_), do: nil

  defp upsert_industry(newest, by_code) do
    {rows, dropped, unmatched} =
      Enum.reduce(newest, {[], 0, 0}, fn {registry_code, row}, {acc, dropped, unmatched} ->
        case Map.get(by_code, registry_code) do
          nil ->
            {acc, dropped, unmatched + 1}

          company_id ->
            case migrate(row) do
              nil -> {[{company_id, nil} | acc], dropped + 1, unmatched}
              code -> {[{company_id, code} | acc], dropped, unmatched}
            end
        end
      end)

    written =
      rows
      |> Enum.chunk_every(@batch)
      |> Enum.reduce(0, fn chunk, acc -> acc + bulk_update_industry(chunk) end)

    Progress.done("LV industry codes written", written)

    {:ok,
     %{
       assigned: length(rows) - dropped,
       dropped: dropped,
       unmatched: unmatched,
       written: written
     }}
  end

  # A Rev-2-only class is Rev. 2 no matter which year it was filed under —
  # that's the 429 stragglers in the 2024 rows. `nace_rev2_to_rev21/1`
  # returns such a code rewritten, and returns a both-revisions code
  # unchanged, so applying it to a Rev-2.1 row is a no-op *except* for
  # collisions — which is exactly why they are short-circuited first.
  defp migrate(%{year: year, code: code}) when year >= @rev21_from_year do
    if NaceMigration.collision?(code) do
      code
    else
      NaceMigration.nace_rev2_to_rev21(code)
    end
  end

  defp migrate(%{code: code}), do: NaceMigration.nace_rev2_to_rev21(code)

  defp bulk_update_industry([]), do: 0

  defp bulk_update_industry(rows) do
    company_ids = Enum.map(rows, fn {id, _} -> Ecto.UUID.dump!(id) end)
    codes = Enum.map(rows, fn {_, code} -> code end)

    sql = """
    UPDATE companies c
    SET industry_code = v.code, updated_at = now()
    FROM unnest($1::uuid[], $2::text[]) AS v(id, code)
    WHERE c.id = v.id AND c.industry_code IS DISTINCT FROM v.code
    """

    %{num_rows: n} = Ecto.Adapters.SQL.query!(Repo, sql, [company_ids, codes])
    n
  end
end
