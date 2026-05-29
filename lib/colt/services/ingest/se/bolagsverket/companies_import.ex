defmodule Colt.Services.Ingest.Se.Bolagsverket.CompaniesImport do
  @moduledoc """
  Pages Bolagsverket's HVD `/organisationer` endpoint, normalises each
  organisation record, and bulk-upserts via `Company.upsert_full`.

  The endpoint is `POST` (it accepts a JSON filter body so a single call
  can fetch many orgs); we walk pagination cursors until exhausted.

  Run-shaping:
    * `Application.get_env(:colt, :bolagsverket_se_max_companies, nil)` caps
      the total number of orgs imported per run (set in dev / slice
      verification to keep iterations cheap).

  Rate limit: 60 req/min per client, enforced by the API. We don't add
  client-side throttling here — page size is 100 so this comfortably
  fits 60×100 = 6,000 orgs/min worst case.
  """

  require Logger

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Progress
  alias Colt.Services.Ingest.Sample

  @list_url "https://gw.api.bolagsverket.se/vardefulla-datamangder/v1/organisationer"
  @page_size 100
  @batch 500

  def run(token) when is_binary(token) do
    cap = Application.get_env(:colt, :bolagsverket_se_max_companies)

    count =
      stream_pages(token)
      |> Stream.flat_map(& &1)
      |> Progress.tick("BV organisations read")
      |> Stream.map(&map_company/1)
      |> Stream.reject(&is_nil/1)
      |> Stream.filter(&Sample.included?(&1.registry_code))
      |> maybe_take(cap)
      |> Stream.chunk_every(@batch)
      |> Enum.reduce(0, fn chunk, n ->
        Ash.bulk_create!(chunk, Company, :upsert_full,
          return_errors?: true,
          stop_on_error?: true
        )

        n + length(chunk)
      end)

    Progress.done("BV companies upserted", count)
    {:ok, %{processed: count}}
  end

  defp maybe_take(stream, nil), do: stream
  defp maybe_take(stream, n) when is_integer(n), do: Stream.take(stream, n)

  # ---- pagination ----

  defp stream_pages(token) do
    Stream.unfold(nil, fn
      :done ->
        nil

      cursor ->
        case fetch_page(token, cursor) do
          {:ok, items, next} ->
            {items, next || :done}

          :error ->
            nil
        end
    end)
  end

  defp fetch_page(token, cursor) do
    body = page_body(cursor)

    case Req.post(@list_url,
           headers: [
             {"authorization", "Bearer #{token}"},
             {"content-type", "application/json"}
           ],
           json: body,
           receive_timeout: 60_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: payload}} ->
        items = Map.get(payload, "organisationer", [])
        next = next_cursor(payload)
        {:ok, items, next}

      other ->
        Logger.warning(
          "BV organisationer fetch failed cursor=#{inspect(cursor)}: #{inspect(other)}"
        )

        :error
    end
  end

  defp page_body(nil), do: %{"sokresultatPerSida" => @page_size}
  defp page_body(cursor), do: %{"sokresultatPerSida" => @page_size, "nasta" => cursor}

  defp next_cursor(payload) do
    # HVD pagination key varies by docs version; accept either.
    payload["nasta"] || payload["nextCursor"] || nil
  end

  # ---- record → Company params ----

  defp map_company(json) do
    with code when is_binary(code) <-
           get_in(json, ["organisationsidentitet", "identitetsbeteckning"]) ||
             json["organisationsnummer"],
         name when is_binary(name) and name != "" <- pick_name(json) do
      %{
        registry_code: normalise_code(code),
        market: :se,
        name: name,
        region: pick_city(json),
        status: derive_status(json),
        industry_code: pick_sni(json),
        website_url: nil,
        website_source: nil
      }
    else
      _ -> nil
    end
  end

  # Strip the Swedish org-number formatting ("556012-5790" → "5560125790").
  defp normalise_code(code) do
    code
    |> String.replace(~r/[^0-9A-Za-z]/, "")
    |> :binary.copy()
  end

  defp pick_name(json) do
    name =
      get_in(json, ["organisationsnamn", "namn"]) ||
        json["organisationsnamn"] ||
        json["firma"]

    if is_binary(name) and name != "", do: :binary.copy(name), else: nil
  end

  defp pick_city(json) do
    city =
      get_in(json, ["postadress_organisation", "postort"]) ||
        get_in(json, ["postadress", "postort"]) ||
        json["postort"]

    if is_binary(city) and city != "", do: :binary.copy(city), else: nil
  end

  # SNI is a 5-digit Swedish industry code (the analogue of NACE).
  # The HVD response surfaces it under `verksamhet` / `naringsgren`; we
  # accept either array or string forms and keep the first code.
  defp pick_sni(json) do
    candidates =
      [
        get_in(json, ["verksamhetsbeskrivning", "naringsgrenskod"]),
        get_in(json, ["naringsgren", "kod"]),
        json["sni_kod"],
        json["sni"]
      ]
      |> List.flatten()
      |> Enum.reject(&(&1 in [nil, ""]))

    case candidates do
      [first | _] when is_binary(first) -> :binary.copy(first)
      _ -> nil
    end
  end

  defp derive_status(json) do
    avregistrerad =
      json["avregistreringsdatum"] || get_in(json, ["registrering", "avregistreringsdatum"])

    cond do
      avregistrerad not in [nil, ""] -> :deleted
      true -> :registered
    end
  end
end
