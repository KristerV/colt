defmodule Colt.Services.Ingest.Lt.Sodra.Harvest do
  @moduledoc """
  Harvests per-company data from Sodra's "Atviri įmonių duomenys" JSON API
  (`atvira.sodra.lt/imones-rest/solr/page`) through the stealth browser
  (`Colt.Services.Browser`). This is the real per-company source — it returns, for
  every active employer (~49k), the legal-entity code, insured-persons count
  (headcount) **and** the EVRK economic-activity code (= NACE).

  The API sits behind a Cloudflare managed challenge, so it must be reached through
  the browser sidecar; plain `Req` gets a 403 challenge. The whole page-loop runs
  inside the cleared browser context (one CF clear, then N JSON fetches).

  Returns `{:ok, [%{registry_code, employees, evrk, month}]}`.
  """

  require Logger

  alias Colt.Services.Browser

  # Opening this page clears the Cloudflare challenge for the origin; the API calls
  # below are then same-origin `fetch()`es from inside the page.
  @page_url "https://atvira.sodra.lt/imones/detali-paieska/index.html"
  @page_size 2000
  @max_pages 40

  def run(opts \\ []) do
    max_pages = Keyword.get(opts, :max_pages, @max_pages)

    with {:ok, raw} when is_list(raw) <-
           Browser.eval(@page_url, harvest_js(@page_size, max_pages), timeout_ms: 300_000) do
      rows = raw |> Enum.map(&normalize/1) |> Enum.reject(&is_nil/1)
      Logger.info("Sodra harvest: #{length(rows)} company rows")
      {:ok, rows}
    else
      {:ok, other} -> {:error, {:unexpected_harvest_shape, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  # In-page loop: page the Solr API by `page`/`size` until every element is fetched
  # (or max_pages), returning compact rows. `evrk` is published as a float like
  # 702000.0 (6-digit EVRK); we round it to an int and format to NACE on the Elixir side.
  defp harvest_js(size, max_pages) do
    """
    const base = (p) => "/imones-rest/solr/page?text=&minAvgWage=&maxAvgWage=&minNumInsured=&maxNumInsured=&municipality=&evrk=&size=#{size}&page=" + p;
    let rows = [], total = null, page = 0;
    while (page < #{max_pages}) {
      const r = await fetch(base(page), { headers: { Accept: "application/json" } });
      if (r.status !== 200) throw new Error("sodra api status " + r.status);
      const j = await r.json();
      total = j.totalElements;
      const c = j.content || [];
      if (c.length === 0) break;
      for (const x of c) rows.push({ jar: x.jarCode, emp: x.lastNumInsured, evrk: (x.evrk == null ? null : Math.round(x.evrk)), month: x.month });
      page++;
      if (rows.length >= total) break;
    }
    return rows;
    """
  end

  defp normalize(%{"jar" => jar} = row) when is_binary(jar) and jar != "" do
    %{
      registry_code: jar,
      employees: pos_int(row["emp"]),
      # EVRK 6-digit as a bare-digit string (e.g. "702000"); nil / 0 => no code.
      # The NACE filter matches on LEFT(industry_code, 4), so no dots / trimming.
      evrk: evrk_string(row["evrk"]),
      # Sodra "month" is YYYYMM (e.g. 202605); fiscal year for the AnnualReport row.
      year: year_of(row["month"])
    }
  end

  defp normalize(_), do: nil

  defp pos_int(n) when is_integer(n) and n > 0, do: n
  defp pos_int(_), do: nil

  defp evrk_string(n) when is_integer(n) and n > 0, do: Integer.to_string(n)
  defp evrk_string(_), do: nil

  defp year_of(m) when is_integer(m) and m >= 190_000, do: div(m, 100)
  defp year_of(_), do: nil
end
