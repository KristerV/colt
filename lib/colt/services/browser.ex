defmodule Colt.Services.Browser do
  @moduledoc """
  Client for the single stealth-browser sidecar (`browser/server.mjs`, patchright
  under Xvfb). This is the one browser for all scraping — it replaces the CDP/chromium
  and Wallaby paths and clears Cloudflare managed challenges those cannot.

  Two entry points:

    * `fetch_html/2` — render a URL and return `{:ok, %{html, status, final_url}}`,
      the same contract the old `Scrape.Cdp` returned. Used by `Scrape.Fetch`.
    * `eval/3` — navigate to a URL (clearing Cloudflare), then run a JS async-function
      body in the page context and return its decoded JSON value. Used by scrapers that
      page a JSON API from inside the cleared origin (e.g. Sodra).

  The sidecar listens on localhost only; base URL from `COLT_BROWSER_URL`
  (default `http://127.0.0.1:8791`).
  """

  require Logger

  @default_base "http://127.0.0.1:8791"
  @fetch_timeout_ms 60_000
  @eval_timeout_ms 180_000

  @doc "Render `url` and return `{:ok, %{html, status, final_url}}`."
  def fetch_html(url, opts \\ []) when is_binary(url) do
    timeout = Keyword.get(opts, :timeout_ms, @fetch_timeout_ms)

    with {:ok, %{"html" => html} = body} <-
           post("/fetch", %{url: url, timeout_ms: timeout}, timeout) do
      {:ok, %{html: html, status: 200, final_url: body["url"] || url}}
    end
  end

  @doc """
  Navigate to `url` (clearing Cloudflare), run `fn_body` (a JS async-function body that
  `return`s a JSON-serializable value) in the page context, and return `{:ok, value}`.
  """
  def eval(url, fn_body, opts \\ []) when is_binary(url) and is_binary(fn_body) do
    timeout = Keyword.get(opts, :timeout_ms, @eval_timeout_ms)

    with {:ok, %{"result" => result}} <-
           post("/eval", %{url: url, fn: fn_body, timeout_ms: timeout}, timeout) do
      {:ok, result}
    end
  end

  @doc "Liveness probe for the sidecar."
  def healthy? do
    case Req.get(base_url() <> "/health", receive_timeout: 5_000, retry: false) do
      {:ok, %{status: 200, body: %{"ok" => true}}} -> true
      _ -> false
    end
  end

  defp post(path, payload, timeout) do
    # retry: false — the caller (Oban worker) owns retry semantics; a browser fetch is
    # slow and we don't want Req silently re-running a 3-minute page load.
    case Req.post(base_url() <> path,
           json: payload,
           receive_timeout: timeout + 10_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        reason = (is_map(body) && body["error"]) || "http_#{status}"
        Logger.warning("Browser sidecar #{path} -> #{status}: #{inspect(reason)}")
        {:error, {:browser, reason}}

      {:error, reason} ->
        Logger.warning("Browser sidecar #{path} unreachable: #{inspect(reason)}")
        {:error, {:browser_unreachable, reason}}
    end
  end

  defp base_url, do: System.get_env("COLT_BROWSER_URL", @default_base)
end
