defmodule Colt.Services.Sending.LastThreadMessageId do
  @moduledoc """
  Find the Nylas message id to thread the next outbound send against:
  the most recent inbound reply on the thread, falling back to the most
  recently sent outbound email. Used to populate `reply_to_message_id`
  so Nylas/the provider stitches the send into the existing conversation
  instead of starting a new one.
  """

  alias Colt.Resources.{InboundEmail, OutboundEmail}

  def run(thread_id) when is_binary(thread_id) do
    with {:ok, nil} <- last_inbound(thread_id),
         {:ok, nil} <- last_outbound(thread_id) do
      {:ok, nil}
    else
      {:ok, id} -> {:ok, id}
      err -> err
    end
  end

  defp last_inbound(thread_id) do
    case InboundEmail.list_for_thread(thread_id, authorize?: false) do
      {:ok, rows} ->
        rows
        |> Enum.sort_by(& &1.received_at, {:desc, DateTime})
        |> List.first()
        |> case do
          %{nylas_message_id: id} when is_binary(id) -> {:ok, id}
          _ -> {:ok, nil}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp last_outbound(thread_id) do
    case OutboundEmail.list_for_thread(thread_id, authorize?: false) do
      {:ok, rows} ->
        rows
        |> Enum.filter(&(&1.status == :sent and &1.nylas_message_id))
        |> Enum.sort_by(& &1.sent_at, {:desc, DateTime})
        |> List.first()
        |> case do
          %{nylas_message_id: id} -> {:ok, id}
          _ -> {:ok, nil}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
