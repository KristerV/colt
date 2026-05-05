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
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: status, body: body} = resp}
      when status in 200..299 and is_binary(body) ->
        {:ok, %{html: body, status: status, final_url: final_url(resp, url)}}

      {:ok, %Req.Response{status: status, body: body} = resp} when is_binary(body) ->
        {:ok, %{html: body, status: status, final_url: final_url(resp, url)}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp final_url(%Req.Response{} = resp, fallback) do
    case Req.Response.get_private(resp, :req_request) do
      %Req.Request{url: %URI{} = uri} -> URI.to_string(uri)
      _ -> fallback
    end
  end
end
