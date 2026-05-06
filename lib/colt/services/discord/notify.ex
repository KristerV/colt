defmodule Colt.Services.Discord.Notify do
  @moduledoc """
  Fire-and-forget Discord webhook notifier. Reads webhook URL from
  `config :colt, :discord_webhook_url`. If unset, the call is a no-op so
  dev/test runs don't depend on the network.
  """

  require Logger

  def run(content) when is_binary(content) do
    case Application.get_env(:colt, :discord_webhook_url) do
      url when is_binary(url) and url != "" ->
        Task.start(fn -> post(url, content) end)
        {:ok, :enqueued}

      _ ->
        {:ok, :skipped}
    end
  end

  defp post(url, content) do
    case Req.post(url, json: %{content: content}, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("discord webhook non-2xx #{status}: #{inspect(body)}")

      {:error, reason} ->
        Logger.warning("discord webhook failed: #{inspect(reason)}")
    end
  end
end
