defmodule Colt.Services.Scrape.Fetch do
  @moduledoc """
  Top-level fetcher. Tries `Static` first, runs `DetectSpa` on the result, and
  falls back to `Wallaby` if needed. Adds a small jitter delay before the
  request as a politeness default.

  Returns
      {:ok, %{html, fetcher: :static | :wallaby, status, final_url}}
      | {:error, reason}
  """

  alias Colt.Services.Scrape.{Cdp, DetectSpa, Static}

  @default_jitter_ms 250

  def run(url, opts \\ []) when is_binary(url) do
    jitter = Keyword.get(opts, :jitter_ms, @default_jitter_ms)
    if jitter > 0, do: Process.sleep(:rand.uniform(jitter))

    url = normalize_url(url)

    with {:ok, static} <- Static.run(url),
         {:ok, verdict} <- DetectSpa.run(static) do
      case verdict do
        :static ->
          {:ok, Map.put(static, :fetcher, :static)}

        :needs_wallaby ->
          case Cdp.run(url) do
            {:ok, rendered} -> {:ok, Map.put(rendered, :fetcher, :cdp)}
            # Fall back to whatever static gave us rather than failing the whole pipeline.
            {:error, _reason} -> {:ok, Map.put(static, :fetcher, :static)}
          end
      end
    end
  end

  # Percent-encode non-ASCII path/query bytes. HTTP clients (Mint) and Chromium's
  # CDP both reject request targets containing raw UTF-8 (e.g. `/ru/контакты`).
  defp normalize_url(url) do
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
