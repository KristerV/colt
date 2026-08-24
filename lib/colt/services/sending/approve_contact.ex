defmodule Colt.Services.Sending.ApproveContact do
  @moduledoc """
  Move one CampaignContact from :pending_approval → :approved, applying
  whatever text edits the human made in the writing view first.

  The template is passed via `sequence_id:` in opts — the template the user
  was working in. Stamping it on the contact scopes future learning.

  Drafting already happened earlier, when the human opened the writing view
  (`write_live.ex` → `StickyInbox` → `EmailWriter`) — this module only picks
  up from there: apply edits, then hand off to `FinalizeApproval` for the
  tail shared with the cron-driven auto-approve path (snapshot, approve,
  schedule, mark approved, record the status transition).
  """

  alias Colt.Resources.{CampaignContact, Sequence}
  alias Colt.Services.Sending.{FinalizeApproval, StickyInbox}

  def run(contact_id, edits, opts \\ []) when is_binary(contact_id) and is_map(edits) do
    actor = Keyword.get(opts, :actor)
    sequence_id = Keyword.get(opts, :sequence_id)

    with {:ok, contact} <- load_contact(contact_id, actor),
         {:ok, sequence} <- load_sequence(sequence_id, contact.campaign_id, actor),
         {:ok, inbox} <- StickyInbox.run(contact, actor: actor) do
      FinalizeApproval.run(contact, sequence, inbox, edits, actor: actor, auto_approved?: false)
    end
  end

  defp load_contact(id, actor) do
    Ash.get(CampaignContact, id,
      load: [:thread],
      actor: actor,
      authorize?: actor != nil
    )
  end

  defp load_sequence(sequence_id, _campaign_id, actor) when is_binary(sequence_id) do
    {:ok,
     Sequence.get!(sequence_id,
       load: [:sequence_steps],
       actor: actor,
       authorize?: actor != nil
     )}
  end

  defp load_sequence(_nil, campaign_id, actor) do
    {:ok,
     Sequence.get_for_campaign!(campaign_id,
       load: [:sequence_steps],
       actor: actor,
       authorize?: actor != nil
     )}
  end
end
