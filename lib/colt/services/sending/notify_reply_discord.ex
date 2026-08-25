defmodule Colt.Services.Sending.NotifyReplyDiscord do
  @moduledoc """
  Discord-alert on a real reply worth interrupting for: the contact is newly
  `:interested`, or was already in the sales funnel (any reply there is a
  live conversation, not just an OOO or a decline). Scoped to my own
  campaigns — the one Discord webhook is mine, not a per-user notification
  system.
  """

  alias Colt.Services.Discord.Notify

  @my_user_id "4f186d06-25d3-4c02-94e6-f10f188f4fe0"

  def run(contact, category) do
    cond do
      contact.campaign.owner_id != @my_user_id -> {:ok, :not_mine}
      contact.in_funnel_sales? or category == :interested -> notify(contact, category)
      true -> {:ok, :skipped}
    end
  end

  defp notify(contact, category) do
    who = (contact.person && (contact.person.name || contact.person.email)) || "someone"

    Notify.run(
      "#{who} replied (#{category}) on #{contact.campaign.name} — " <>
        "https://liid.ee/campaigns/#{contact.campaign_id}/sales"
    )

    {:ok, :notified}
  end
end
