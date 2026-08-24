defmodule Colt.Services.Sending.AutoDraftAndApprove do
  @moduledoc """
  Drives one CampaignContact straight to `:approved` + step-1 scheduled
  without ever entering the writing view. Called synchronously by
  `Colt.Jobs.AutoApproveCampaign`, once per open send slot.

  Pass `inbox_id:` to pin the sending inbox (the starter does, so the email
  schedules into the same account the slot was counted against); omit it and
  the sticky picker chooses. A no-op (`{:ok, :skipped}`) if the contact has
  already left `:pending_approval`, and `{:error, :not_in_sending_funnel}`
  if it isn't in the sending funnel at all.

  Steps:
    1. Pick the least-sent active, already-seeded variant (fair A/B rotation).
    2. Resolve the sticky inbox (pinned or picked) and stick it to the
       contact — before the writer runs, so it composes in the actual
       sender's name instead of a generic, unsigned draft.
    3. Run EmailWriter for that variant to create drafted emails.
    4. Hand off to FinalizeApproval: snapshot the variant, approve with
       `auto_approved?: true`, schedule step 1, mark the rest approved,
       record the status transition.

  Steps 2 and 4 are shared with the manual approve path (ApproveContact) —
  see StickyInbox and FinalizeApproval. This module only owns what's
  actually specific to the cron trigger: picking a template variant and
  running the writer with no human review in between.
  """

  alias Colt.Resources.{CampaignContact, OutboundEmail, Sequence}
  alias Colt.Services.Sending.{EmailWriter, EnsureInSendingFunnel, FinalizeApproval, StickyInbox}

  def run(contact_id, opts \\ []) when is_binary(contact_id) do
    actor = Keyword.get(opts, :actor)
    inbox_id = Keyword.get(opts, :inbox_id)

    with {:ok, contact} <- load_contact(contact_id, actor),
         {:ok, contact} <- EnsureInSendingFunnel.run(contact),
         :pending_approval <- contact.status,
         {:ok, sequence} <- pick_template(contact.campaign_id, actor),
         {:ok, inbox} <- StickyInbox.run(contact, inbox_id: inbox_id, actor: actor),
         {:ok, _} <- EmailWriter.run(contact_id, sequence_id: sequence.id, actor: actor),
         {:ok, contact} <- load_contact(contact_id, actor) do
      FinalizeApproval.run(contact, sequence, inbox, %{}, actor: actor, auto_approved?: true)
    else
      # Already started (e.g. a manual approve grabbed it first) — no-op, not
      # an error. The contact's status guard short-circuits the chain.
      status when is_atom(status) -> {:ok, :skipped}
      other -> other
    end
  end

  # Fair A/B rotation: among active variants that have been written at least
  # once, pick the one sent to the fewest contacts (ties → oldest) so sample
  # sizes stay balanced. Unseeded variants are skipped — never send blanks.
  defp pick_template(campaign_id, actor) do
    active =
      Sequence.list_enabled_for_campaign!(campaign_id, actor: actor, authorize?: actor != nil)
      |> Enum.filter(&seeded?(&1, actor))

    case active do
      [] ->
        {:error, :no_enabled_template}

      pool ->
        counts = sent_counts(campaign_id, actor)
        picked = Enum.min_by(pool, &Map.get(counts, &1.id, 0))

        Sequence.get(picked.id,
          load: [:sequence_steps],
          actor: actor,
          authorize?: actor != nil
        )
    end
  end

  # Contacts already committed to each variant (sequence_id stamped at approval).
  defp sent_counts(campaign_id, actor) do
    case CampaignContact.list_for_campaign(campaign_id, actor: actor, authorize?: actor != nil) do
      {:ok, contacts} ->
        contacts
        |> Enum.reject(&is_nil(&1.sequence_id))
        |> Enum.frequencies_by(& &1.sequence_id)

      _ ->
        %{}
    end
  end

  defp seeded?(sequence, actor) do
    case OutboundEmail.list_user_edited_for_sequence(sequence.id, 1,
           actor: actor,
           authorize?: actor != nil
         ) do
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end

  defp load_contact(id, actor) do
    Ash.get(CampaignContact, id, load: [:thread], actor: actor, authorize?: actor != nil)
  end
end
