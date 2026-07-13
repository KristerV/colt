defmodule Colt.Services.Scrape.Fetch do
  @moduledoc """
  Top-level fetcher. Tries `Static` first, runs `DetectSpa` on the result, and
  falls back to `Wallaby` if needed. Adds a small jitter delay before the
  request as a politeness default.

  Returns
      {:ok, %{html, fetcher: :static | :browser, status, final_url}}
      | {:error, reason}
  """

  alias Colt.Services.Browser
  alias Colt.Services.Scrape.{DetectSpa, Static}

  @default_jitter_ms 250

  def run(url, opts \\ []) when is_binary(url) do
    jitter = Keyword.get(opts, :jitter_ms, @default_jitter_ms)
    if jitter > 0, do: Process.sleep(:rand.uniform(jitter))

    url = normalize_url(url)

    with {:ok, static} <- Static.run(url),
         {:ok, verdict} <- DetectSpa.run(static) do
      case verdict do
        :static ->
          {:ok, scrub(static, :static)}

        :needs_wallaby ->
          case Browser.fetch_html(url) do
            {:ok, rendered} -> {:ok, scrub(rendered, :browser)}
            # Fall back to whatever static gave us rather than failing the whole pipeline.
            {:error, _reason} -> {:ok, scrub(static, :static)}
          end
      end
    end
  end

  # Tag the fetcher and strip NUL bytes from the HTML. Postgres text/jsonb
  # cannot store the NUL character, so leaving them in would blow up downstream
  # inserts (Page markdown, ExtractNavigation Oban args) with a 22P05 error.
  defp scrub(%{html: html} = result, fetcher) when is_binary(html) do
    %{result | html: String.replace(html, <<0>>, "")} |> Map.put(:fetcher, fetcher)
  end

  defp scrub(result, fetcher), do: Map.put(result, :fetcher, fetcher)

  # Percent-encode non-ASCII path/query bytes. HTTP clients (Mint) and Chromium's
  # CDP both reject request targets containing raw UTF-8 (e.g. `/ru/контакты`).
  # Also prepend a scheme — bare hosts (`estmaterminal.ee`) are rejected by Finch.
  defp normalize_url(url) do
    url
    |> ensure_scheme()
    |> percent_encode()
  end

  # Treat a URL without an explicit scheme as https. `URI.parse/1` leaves
  # `scheme: nil` for `estmaterminal.ee` or `example.com/path`, where the host
  # ends up parsed as the path.
  defp ensure_scheme(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when is_binary(scheme) -> url
      _ -> "https://" <> url
    end
  end

  defp percent_encode(url) do
    if ascii?(url) do
      url
    else
      uri = URI.parse(url)

      %{
        uri
        | path: uri.path && encode_path(uri.path),
          query: uri.query && URI.encode(uri.query)
      }
      |> URI.to_string()
    end
  end

  defp ascii?(<<>>), do: true
  defp ascii?(<<c, rest::binary>>) when c < 128, do: ascii?(rest)
  defp ascii?(_), do: false

  defp encode_path(path) do
    path
    |> String.split("/")
    |> Enum.map_join("/", &URI.encode/1)
  end
end
