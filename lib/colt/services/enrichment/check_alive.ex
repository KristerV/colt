defmodule Colt.Services.Enrichment.CheckAlive do
  @moduledoc """
  Liveness check on a candidate website URL. HEAD first; falls back to GET
  on 4xx/5xx for sites that hate HEAD. Returns `:alive | :dead`.
  """

  @user_agent "LiidBot/1.0 (+https://liid.app; contact@liid.app)"
  @alive_statuses [200, 301, 302, 303, 307, 308]
  @timeout 10_000

  def run(nil), do: {:ok, :dead}
  def run(""), do: {:ok, :dead}

  def run(url) when is_binary(url) do
    case normalize(url) do
      {:ok, normalized} ->
        case head(normalized) do
          {:ok, status} when status in @alive_statuses -> {:ok, :alive}
          _ -> get_fallback(normalized)
        end

      :error ->
        {:ok, :dead}
    end
  end

  defp normalize(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        encoded = host |> String.to_charlist() |> :idna.encode() |> List.to_string()
        {:ok, URI.to_string(%{uri | host: encoded})}

      _ ->
        :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp head(url) do
    case Req.head(url, headers: ua(), redirect: true, receive_timeout: @timeout) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp get_fallback(url) do
    case Req.get(url,
           headers: ua(),
           redirect: true,
           receive_timeout: @timeout,
           into: <<>>
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> {:ok, :alive}
      _ -> {:ok, :dead}
    end
  rescue
    _ -> {:ok, :dead}
  catch
    _, _ -> {:ok, :dead}
  end

  defp ua, do: [{"user-agent", @user_agent}]
end
