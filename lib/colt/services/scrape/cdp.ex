defmodule Colt.Services.Scrape.Cdp do
  @moduledoc """
  CDP-based fetcher. Connects to the long-lived Chromium booted by
  `rel/overlays/bin/entrypoint.sh` on `--remote-debugging-port` (default 9222).

  Each fetch opens a new target (tab), navigates, waits for the load event,
  reads `document.documentElement.outerHTML`, and closes the target. Pays the
  Chrome cold-start cost once at container boot, not per page.

  Returns `{:ok, %{html, final_url, status: 200}}` on success, mirroring
  `Colt.Services.Scrape.Wallaby` so `Colt.Services.Scrape.Fetch` can swap
  between them.
  """

  alias ChromeRemoteInterface.PageSession
  alias ChromeRemoteInterface.RPC.{Page, Runtime}
  alias ChromeRemoteInterface.Session

  @default_host "127.0.0.1"
  @default_port 9222
  @load_timeout 15_000

  def run(url) when is_binary(url) do
    server = Session.new(host: host(), port: port())

    with {:ok, %{"id" => page_id} = page} <- new_page(server),
         {:ok, page_pid} <- PageSession.start_link(page) do
      try do
        fetch(page_pid, url)
      after
        PageSession.stop(page_pid)
        Session.close_page(server, page_id)
      end
    end
  rescue
    e -> {:error, "cdp: #{Exception.message(e)}"}
  catch
    :exit, reason -> {:error, "cdp exit: #{inspect(reason)}"}
  end

  defp fetch(page_pid, url) do
    {:ok, _} = Page.enable(page_pid)
    :ok = PageSession.subscribe(page_pid, "Page.loadEventFired")

    {:ok, _} = Page.navigate(page_pid, %{url: url})

    receive do
      {:chrome_remote_interface, "Page.loadEventFired", _} -> :ok
    after
      @load_timeout -> :ok
    end

    {:ok, %{"result" => %{"result" => %{"value" => html}}}} =
      Runtime.evaluate(page_pid, %{
        expression: "document.documentElement.outerHTML",
        returnByValue: true
      })

    final_url =
      case Runtime.evaluate(page_pid, %{
             expression: "document.location.href",
             returnByValue: true
           }) do
        {:ok, %{"result" => %{"result" => %{"value" => u}}}} -> u
        _ -> url
      end

    {:ok, %{html: html, status: 200, final_url: final_url}}
  end

  # chrome_remote_interface's Session.new_page/1 uses GET, but recent Chromium
  # requires PUT for /json/new and returns 405 otherwise. Call it directly.
  defp new_page(server) do
    url = "http://#{server.host}:#{server.port}/json/new"

    case Req.put(url, decode_body: :json) do
      {:ok, %Req.Response{status: 200, body: %{"id" => _} = page}} -> {:ok, page}
      {:ok, %Req.Response{status: s, body: b}} -> {:error, "cdp /json/new #{s}: #{inspect(b)}"}
      {:error, reason} -> {:error, "cdp /json/new: #{inspect(reason)}"}
    end
  end

  defp host, do: System.get_env("CHROME_HOST") || @default_host
  defp port, do: (System.get_env("CHROME_PORT") || "#{@default_port}") |> String.to_integer()
end
