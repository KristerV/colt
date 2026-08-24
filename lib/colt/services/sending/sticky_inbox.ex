defmodule Colt.Services.Sending.StickyInbox do
  @moduledoc """
  Resolves the sending inbox for a CampaignContact and sticks it, once.
  Reuses `assigned_email_account_id` if the contact already has one;
  otherwise picks via AssignInbox and persists it via the `:assign_inbox`
  action. Every caller that needs "the sender this contact writes/sends
  as" goes through here — EmailWriter needs it resolved before drafting so
  the sequence is signed correctly, and approval needs the same account to
  schedule against.

  Pass `inbox_id:` to pin a specific inbox (skips the sticky picker) — used
  by the cron starter, which already picked the inbox its capacity check
  counted against.
  """

  alias Colt.Resources.{CampaignContact, EmailAccount}
  alias Colt.Services.Sending.AssignInbox

  def run(contact, opts \\ [])

  def run(%{assigned_email_account_id: id}, opts) when is_binary(id) do
    actor = Keyword.get(opts, :actor)
    EmailAccount.get(id, actor: actor, authorize?: actor != nil)
  end

  def run(contact, opts) do
    actor = Keyword.get(opts, :actor)
    inbox_id = Keyword.get(opts, :inbox_id)

    with {:ok, inbox} <- resolve(inbox_id, contact.campaign_id, actor),
         {:ok, _contact} <-
           CampaignContact.assign_inbox(contact, inbox.id, actor: actor, authorize?: actor != nil) do
      {:ok, inbox}
    end
  end

  defp resolve(nil, campaign_id, actor), do: AssignInbox.run(campaign_id, actor: actor)

  defp resolve(inbox_id, _campaign_id, actor) when is_binary(inbox_id),
    do: EmailAccount.get(inbox_id, actor: actor, authorize?: actor != nil)
end
