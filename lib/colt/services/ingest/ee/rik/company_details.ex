defmodule Colt.Services.Ingest.Ee.Rik.CompanyDetails do
  @moduledoc """
  Streams `yldandmed.json` (Estonian business registry "general data") and
  bulk-upserts website / industry / registry email onto `Colt.Resources.Company`.

  The EMAIL contact-means lands in `:registry_email`, *not* `:generic_email` —
  the latter is reserved for the `info@`-style inbox scraped from the company's
  own site. Keeping them apart matters: the registry address is frequently a
  personal one (the owner's), and it is the owner rung's only candidate today.
  See `docs/specs/contact-acquisition.md`.

  Uses the `:upsert_details` action with `upsert_fields` limited to the
  detail columns, so any registry-side fields written by `CompaniesImport`
  (name, region, status) are preserved on conflict.
  """

  alias Colt.Filters.NaceMigration
  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Ee.Rik.JsonRecordStream
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @filename "yldandmed.json"
  @batch 500

  @peek_regex ~r/"ariregistri_kood"\s*:\s*(\d+)/

  def run do
    with {:ok, path} <- locate_file(),
         {:ok, stream} <- JsonRecordStream.run(path, decode: false),
         {:ok, count} <- bulk_upsert(stream) do
      {:ok, %{file: @filename, patched: count}}
    end
  end

  defp locate_file do
    dir = Application.fetch_env!(:colt, :rik_ee_cache_dir)
    path = Path.join(dir, @filename)

    if File.exists?(path), do: {:ok, path}, else: {:error, {:not_found, path}}
  end

  defp bulk_upsert(stream) do
    count =
      stream
      |> Progress.tick("yldandmed records read")
      |> Stream.map(&peek_and_decode/1)
      |> Stream.reject(&is_nil/1)
      |> Stream.map(&extract/1)
      |> Stream.reject(&is_nil/1)
      |> Stream.chunk_every(@batch)
      |> Enum.reduce(0, fn chunk, n ->
        Ash.bulk_create!(chunk, Company, :upsert_details,
          return_errors?: true,
          stop_on_error?: true
        )

        n + length(chunk)
      end)

    Progress.done("companies patched", count)
    {:ok, count}
  end

  defp peek_and_decode(raw) when is_binary(raw) do
    case Regex.run(@peek_regex, raw, capture: :all_but_first) do
      [code] ->
        if Sample.included?(code), do: Jason.decode!(raw), else: nil

      _ ->
        Jason.decode!(raw)
    end
  end

  defp extract(%{"ariregistri_kood" => code, "nimi" => name} = record)
       when not is_nil(code) and is_binary(name) and name != "" do
    yld = Map.get(record, "yldandmed", %{}) || %{}
    website = pick_active(yld["sidevahendid"], "WWW")

    %{
      registry_code: to_string(code),
      market: :ee,
      name: name,
      status: status_atom(yld["staatus"]),
      industry_code: primary_industry(yld["teatatud_tegevusalad"]),
      website_url: website,
      website_source: if(website, do: :registry, else: nil),
      registry_email: pick_active(yld["sidevahendid"], "EMAIL")
    }
  end

  defp extract(_), do: nil

  defp pick_active(nil, _kind), do: nil

  defp pick_active(list, kind) do
    Enum.find_value(list, fn item ->
      if item["liik"] == kind and is_nil(item["lopp_kpv"]), do: item["sisu"]
    end)
  end

  defp primary_industry(nil), do: nil

  defp primary_industry(list) do
    list
    |> Enum.find(&(&1["on_pohitegevusala"] == true and is_nil(&1["lopp_kpv"])))
    |> to_rev21()
  end

  # RIK tags every declared activity with the classifier it was filed under:
  # `emtak_versioon` 2 = EMTAK 2008 (NACE Rev. 2), 3 = EMTAK 2025 (NACE Rev. 2.1).
  # The registry never re-classified its back catalogue — a company keeps its 2008
  # code until it next re-declares — so the dump is ~29% Rev 2 and shrinking. We
  # store Rev 2.1 only, and translate the stragglers here rather than teach the
  # filters two vocabularies. Re-running the ingest self-heals as RIK migrates.
  #
  # `emtak_kood` is kept over the published `nace_kood` because it carries the
  # national subclass digit and its first 4 chars are always exactly `nace_kood`
  # (checked against all 414,821 activity records), so `LEFT(industry_code, 4)`
  # still yields the NACE class.
  defp to_rev21(%{"emtak_versioon" => 3, "emtak_kood" => code}), do: code

  defp to_rev21(%{"emtak_versioon" => 2, "emtak_kood" => code}),
    do: NaceMigration.emtak_2008_to_2025(code)

  defp to_rev21(_), do: nil

  defp status_atom("R"), do: :registered
  defp status_atom("L"), do: :liquidation
  defp status_atom("N"), do: :deleted
  defp status_atom(_), do: :other
end
