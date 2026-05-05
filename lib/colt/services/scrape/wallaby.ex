defmodule Colt.Services.Scrape.Wallaby do
  @moduledoc """
  Wallaby (Chromedriver) fallback fetcher for SPA / JS-heavy pages.

  Returns `{:ok, %{html, final_url, status: 200}}` on success. The returned
  `html` is the rendered DOM after the page settles.

  Configuration: requires Chromedriver on PATH. See `priv/scripts/dev_helpers.exs`
  for the dev setup blurb.
  """

  @page_timeout 10_000

  def run(url) when is_binary(url) do
    ensure_started()

    try do
      case start_session() do
        {:ok, session} ->
          try do
            fetch(session, url)
          after
            Wallaby.end_session(session)
          end

        {:error, reason} ->
          {:error, "wallaby start_session: #{inspect(reason)}"}
      end
    catch
      :exit, reason -> {:error, "wallaby exit: #{inspect(reason)}"}
    end
  end

  defp fetch(session, url) do
    session = Wallaby.Browser.visit(session, url)
    Process.sleep(500)
    html = Wallaby.Browser.page_source(session)
    final_url = Wallaby.Browser.current_url(session)
    {:ok, %{html: html, status: 200, final_url: final_url}}
  rescue
    e -> {:error, "wallaby fetch: #{Exception.message(e)}"}
  end

  defp start_session do
    Wallaby.start_session(window_size: [width: 1280, height: 800], max_wait_time: @page_timeout)
  end

  defp ensure_started do
    try do
      Application.ensure_all_started(:wallaby)
    catch
      _, _ -> :error
    end
  end
end
