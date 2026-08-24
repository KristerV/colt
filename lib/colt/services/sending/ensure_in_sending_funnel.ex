defmodule Colt.Services.Sending.EnsureInSendingFunnel do
  @moduledoc """
  Guards that a CampaignContact is actually in the sending funnel before any
  sending-machine operation (draft, approve, schedule) touches it. `status`
  defaults to `:pending_approval` on every contact row regardless of how it
  got there, so a status check alone will happily draft or approve a
  hand-entered sales-only lead someone is already talking to by phone.
  Funnel membership (`in_funnel_sending?`) is the only honest answer to "may
  we mail this person" — refuse loudly rather than silently proceeding, so a
  caller that shouldn't be here shows up in logs.
  """

  def run(%{in_funnel_sending?: true} = contact), do: {:ok, contact}
  def run(_contact), do: {:error, :not_in_sending_funnel}
end
