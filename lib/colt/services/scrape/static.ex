defmodule Colt.Services.Scrape.Static do
  @moduledoc """
  Static-HTML fetcher. Req with sensible UA + redirect following.
  Returns `{:ok, %{html, status, final_url}}` on any 2xx/3xx-final response.
  """

  @user_agent "LiidBot/1.0 (+https://liid.app; contact@liid.app)"

  def run(url) when is_binary(url) do
    case Req.get(url,
           headers: [{"user-agent", @user_agent}],
           redirect: true,
           receive_timeout: 60_000,
           retry: false
         ) do
      {:ok, %Req.Response{status: status, body: body} = resp}
      when status in 200..299 and is_binary(body) ->
        {:ok, %{html: to_utf8(body), status: status, final_url: final_url(resp, url)}}

      {:ok, %Req.Response{status: status, body: body} = resp} when is_binary(body) ->
        {:ok, %{html: to_utf8(body), status: status, final_url: final_url(resp, url)}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  # Pages served as Latin-1/Windows-1252 (mislabeled or no charset) leak bytes
  # that aren't valid UTF-8. Drop them so the HTML is safe to store in jsonb.
  defp to_utf8(bin) when is_binary(bin), do: scrub(bin, <<>>)
  defp to_utf8(_), do: ""

  defp scrub(<<>>, acc), do: acc
  defp scrub(<<c::utf8, rest::binary>>, acc), do: scrub(rest, <<acc::binary, c::utf8>>)
  defp scrub(<<_, rest::binary>>, acc), do: scrub(rest, acc)

  defp final_url(%Req.Response{} = resp, fallback) do
    case Req.Response.get_private(resp, :req_request) do
      %Req.Request{url: %URI{} = uri} -> URI.to_string(uri)
      _ -> fallback
    end
  end
end
