defmodule Colt.Services.Ai.PauseOnCreditExhaustion do
  @moduledoc """
  Halts AI work when OpenRouter reports exhausted credits (HTTP 402).

  Pauses the OpenRouter-consuming Oban queues (`:ai`, `:ai_writer`) so jobs
  stop burning their retries against a dead account, and pings Discord. Running
  jobs finish; enqueued jobs stay enqueued. After topping up credits, resume the
  queues from the Oban dashboard (`/oban`) or `Oban.resume_queue/2`.

  Idempotent: if the queues are already paused (a burst of in-flight jobs all hit
  402 at once) we skip the re-pause and, crucially, the duplicate Discord ping.
  """
  require Logger

  alias Colt.Services.Discord

  @ai_queues [:ai, :ai_writer]

  def run(reason \\ nil) do
    with {:ok, newly_paused} <- pause_unpaused_queues() do
      maybe_notify(newly_paused, reason)
      {:ok, newly_paused}
    end
  end

  defp pause_unpaused_queues do
    newly =
      Enum.filter(@ai_queues, fn queue ->
        not paused?(queue) and pause(queue) == :ok
      end)

    {:ok, newly}
  end

  defp paused?(queue) do
    case Oban.check_queue(queue: queue) do
      %{paused: paused} -> paused
      _ -> false
    end
  rescue
    _ -> false
  end

  defp pause(queue) do
    Oban.pause_queue(queue: queue, local_only: false)
  rescue
    e ->
      Logger.error("failed to pause queue #{queue}: #{Exception.message(e)}")
      :error
  end

  defp maybe_notify([], _reason), do: :ok

  defp maybe_notify(queues, reason) do
    Logger.error("AI paused: OpenRouter credits exhausted, paused #{inspect(queues)}")

    Discord.Notify.run(
      "🛑 OpenRouter credits exhausted — paused AI queues (#{Enum.join(queues, ", ")}). " <>
        "Top up credits, then resume from the Oban dashboard." <>
        if(reason, do: "\n#{reason}", else: "")
    )

    :ok
  end
end
