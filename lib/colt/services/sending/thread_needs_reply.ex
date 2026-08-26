defmodule Colt.Services.Sending.ThreadNeedsReply do
  @moduledoc """
  Whether a thread's most recent activity is an inbound reply we haven't
  answered yet: the latest inbound `received_at` is after the latest sent
  outbound `sent_at` (or there's inbound but no sent outbound at all).
  Drives the "needs reply" dot in the sending funnel contact list.
  """

  alias Colt.Resources.{InboundEmail, OutboundEmail}

  def run(thread_id) when is_binary(thread_id) do
    with {:ok, outbound} <- OutboundEmail.list_for_thread(thread_id, authorize?: false),
         {:ok, inbound} <- InboundEmail.list_for_thread(thread_id, authorize?: false) do
      {:ok, needs_reply?(outbound, inbound)}
    end
  end

  def needs_reply?(outbound, inbound) do
    last_sent_at =
      outbound
      |> Enum.filter(&(&1.status == :sent))
      |> Enum.map(& &1.sent_at)
      |> Enum.reject(&is_nil/1)
      |> latest()

    last_received_at =
      inbound
      |> Enum.map(& &1.received_at)
      |> Enum.reject(&is_nil/1)
      |> latest()

    not is_nil(last_received_at) and
      (is_nil(last_sent_at) or DateTime.compare(last_received_at, last_sent_at) == :gt)
  end

  defp latest([]), do: nil
  defp latest(timestamps), do: Enum.max(timestamps, DateTime)
end
