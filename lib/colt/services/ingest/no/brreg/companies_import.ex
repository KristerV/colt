NimbleCSV.define(Colt.Services.Ingest.No.Brreg.CompaniesImport.CSV,
  separator: ",",
  escape: "\""
)

defmodule Colt.Services.Ingest.No.Brreg.CompaniesImport do
  @moduledoc """
  Streams `enheter_alle.csv` and upserts every Norwegian entity via
  `Company.upsert_full` (identity + industry + region + status in one shot).

  Format notes:
    * Comma-separated, double-quoted, UTF-8, no BOM.
    * Some free-text columns (`aktivitet`, `vedtektsfestetFormaal`,
      `paategninger`) embed literal newlines inside quoted strings, so
      `wc -l` overcounts and `File.stream!(..., :line)` is wrong. We use
      `NimbleCSV.parse_stream/1` which is line-aware of quotes.
    * 1.16M rows total; 6.1% carry `antallAnsatte`. We upsert *every*
      entity (sole proprietors, foreign branches, etc.) so person/address
      enrichment in other phases works; the revenue stage filters down to
      AS-with-filings on its own.

  See `docs/countries/no.md` for the full schema mapping and the
  industry-code de-dot rationale (`"43.210"` → `"43210"`).
  """

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.No.Brreg.CompaniesImport.CSV
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @batch 500
  @filename "enheter_alle.csv"

  def run do
    with {:ok, path} <- locate_file(),
         {:ok, count} <- stream_and_upsert(path) do
      {:ok, %{file: @filename, processed: count}}
    end
  end

  defp locate_file do
    dir = Application.fetch_env!(:colt, :brreg_no_cache_dir)
    path = Path.join(dir, @filename)
    if File.exists?(path), do: {:ok, path}, else: {:error, {:not_found, path}}
  end

  defp stream_and_upsert(path) do
    headers = read_headers(path)
    idx = column_index(headers)

    count =
      path
      |> File.stream!(read_ahead: 256 * 1024)
      |> CSV.parse_stream(skip_headers: true)
      |> Progress.tick("BRREG enheter rows read")
      |> Stream.map(&parse_row(&1, idx))
      |> Stream.reject(&is_nil/1)
      |> Stream.filter(&active_when_sampling/1)
      |> Stream.filter(&Sample.included?(&1.registry_code))
      |> Stream.chunk_every(@batch)
      |> Enum.reduce(0, fn chunk, n ->
        Ash.bulk_create!(chunk, Company, :upsert_full,
          return_errors?: true,
          stop_on_error?: true
        )

        n + length(chunk)
      end)

    Progress.done("BRREG companies upserted", count)
    {:ok, count}
  end

  defp read_headers(path) do
    # NimbleCSV.parse_string expects a binary; we read the first line via
    # File.stream! in :line mode, which is safe here because the header
    # row never contains embedded newlines.
    path
    |> File.stream!()
    |> Enum.take(1)
    |> case do
      [line] ->
        line
        |> CSV.parse_string(skip_headers: false)
        |> List.first()
        |> Kernel.||([])

      [] ->
        []
    end
  end

  # Column names → positional indexes. The dump has 90+ columns; we only
  # want a handful. Cheaper to resolve once than to build per-row maps.
  defp column_index(headers) do
    keep = ~w(
      organisasjonsnummer
      navn
      organisasjonsform.kode
      naeringskode1.kode
      hjemmeside
      postadresse.poststed
      forretningsadresse.poststed
      konkurs
      underAvvikling
    )

    headers
    |> Enum.with_index()
    |> Enum.into(%{})
    |> Map.take(keep)
  end

  defp parse_row(fields, idx) do
    code = at(fields, idx, "organisasjonsnummer")
    name = at(fields, idx, "navn")

    cond do
      blank?(code) -> nil
      blank?(name) -> nil
      true -> build_row(fields, idx, code, name)
    end
  end

  defp build_row(fields, idx, code, name) do
    %{
      registry_code: code,
      market: :no,
      name: name,
      region:
        at(fields, idx, "forretningsadresse.poststed")
        |> blank_to_nil()
        |> Kernel.||(at(fields, idx, "postadresse.poststed") |> blank_to_nil()),
      status: derive_status(at(fields, idx, "konkurs"), at(fields, idx, "underAvvikling")),
      industry_code: de_dot(at(fields, idx, "naeringskode1.kode")),
      website_url: normalize_url(at(fields, idx, "hjemmeside")),
      website_source:
        case normalize_url(at(fields, idx, "hjemmeside")) do
          nil -> nil
          _ -> :registry
        end
    }
  end

  defp at(fields, idx, key) do
    case Map.get(idx, key) do
      nil -> nil
      n -> Enum.at(fields, n)
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: if(blank?(s), do: nil, else: String.trim(s))

  # BRREG NACE code format is `"NN.NNN"` (dot at position 3, 5 total
  # digits). Liid's `Company.filtered` uses `LEFT(industry_code, 4)` to
  # match NACE-4 prefixes — feeding it `"43.2"` would break the filter.
  # Strip the dot so `LEFT(_, 4)` gives `"4321"`, matching the shape EE
  # EMTAK stores.
  defp de_dot(nil), do: nil
  defp de_dot(""), do: nil
  defp de_dot(s), do: s |> String.replace(".", "") |> blank_to_nil()

  defp derive_status("true", _), do: :liquidation
  defp derive_status(_, "true"), do: :liquidation
  defp derive_status(_, _), do: :registered

  defp normalize_url(nil), do: nil
  defp normalize_url(""), do: nil

  defp normalize_url(url) do
    trimmed = String.trim(url)

    cond do
      trimmed == "" -> nil
      String.starts_with?(trimmed, "http://") -> trimmed
      String.starts_with?(trimmed, "https://") -> trimmed
      true -> "https://" <> trimmed
    end
  end

  # In dev (sampling on), the BRREG dump is 60% ENK / FLI / NUF (sole
  # props, associations, foreign branches) that rarely have revenue or
  # employees. Dropping ceased rows here keeps the sample populated with
  # rows we can actually test downstream stages on.
  defp active_when_sampling(%{status: :registered}), do: true
  defp active_when_sampling(_), do: not Sample.enabled?()
end
