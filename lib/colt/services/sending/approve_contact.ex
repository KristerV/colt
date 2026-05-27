defmodule Colt.Services.Sending.ApproveContact do
  @moduledoc """
  Move one CampaignContact from :pending_approval → :approved.

  Steps (run/2):
    1. Load contact + sequence + draft emails.
    2. Apply pending user edits (subject, body per step).
    3. Pick sticky inbox.
    4. Snapshot the current sequence (steps + delays + terminal).
    5. Update the contact: status, assigned_email_account, snapshot, version.
    6. Schedule step 1's Email via the §5.2 burst scheduler. Followups
       stay :approved until the send loop fires step N and schedules N+1.
    7. Mark the rest of the email drafts as :approved (no scheduled_at yet).
    8. Bump campaign.auto_approve_streak iff clean (no edits at all).
  """

  alias Colt.Resources.{Campaign, CampaignContact, OutboundEmail, Sequence}
  alias Colt.Services.Sending.{AssignInbox, NextSlot}

  def run(contact_id, edits, opts \\ []) when is_binary(contact_id) and is_map(edits) do
    actor = Keyword.get(opts, :actor)

    with {:ok, contact} <- load_contact(contact_id, actor),
         {:ok, sequence} <- load_sequence(contact.campaign_id, actor),
         {:ok, drafts} <- load_drafts(contact, actor),
         :ok <- ensure_drafts_present(drafts),
         {:ok, drafts} <- apply_edits(drafts, edits, actor),
         {:ok, inbox} <- AssignInbox.run(contact.campaign_id, actor: actor),
         snapshot = build_snapshot(sequence),
         {:ok, contact} <- approve_contact(contact, inbox, snapshot, sequence.version, actor),
         {:ok, _} <- schedule_step_one(drafts, inbox, actor),
         {:ok, _} <- approve_other_steps(drafts, actor),
         {:ok, _} <- maybe_bump_streak(contact.campaign_id, drafts, actor) do
      {:ok, %{contact_id: contact.id, inbox_id: inbox.id}}
    end
  end

  defp load_contact(id, actor) do
    Ash.get(CampaignContact, id,
      load: [:thread],
      actor: actor,
      authorize?: actor != nil
    )
  end

  defp load_sequence(campaign_id, actor) do
    {:ok,
     Sequence.get_for_campaign!(campaign_id,
       load: [:sequence_steps],
       actor: actor,
       authorize?: actor != nil
     )}
  end

  defp load_drafts(%{thread: nil}, _actor), do: {:ok, []}

  defp load_drafts(%{thread: %{id: tid}}, actor) do
    {:ok,
     OutboundEmail.list_for_thread!(tid, actor: actor, authorize?: actor != nil)
     |> Enum.filter(&(&1.status == :drafted))
     |> Enum.sort_by(& &1.step_position)}
  end

  # edits = %{"subject" => "<single subject>",
  #           "bodies" => %{step_position => body_string}}
  defp apply_edits(drafts, edits, actor) do
    subject = Map.get(edits, "subject")
    bodies = Map.get(edits, "bodies", %{})

    updated =
      Enum.map(drafts, fn email ->
        body = Map.get(bodies, email.step_position) || Map.get(bodies, "#{email.step_position}")
        new_subject = if subject in [nil, ""], do: email.user_subject, else: subject
        new_body = if body in [nil, ""], do: email.user_body, else: body

        if subject_changed?(email, new_subject) or body_changed?(email, new_body) do
          {:ok, e} =
            OutboundEmail.update_user_fields(email, new_subject, new_body,
              actor: actor,
              authorize?: actor != nil
            )

          e
        else
          email
        end
      end)

    {:ok, updated}
  end

  defp subject_changed?(%{user_subject: s}, new), do: s != new
  defp body_changed?(%{user_body: b}, new), do: b != new

  defp build_snapshot(sequence) do
    %{
      "version" => sequence.version,
      "language" => sequence.language,
      "steps" =>
        Enum.map(sequence.sequence_steps, fn s ->
          %{
            "position" => s.position,
            "kind" => Atom.to_string(s.kind),
            "delay_days" => s.delay_days,
            "terminal_action" => s.terminal_action && Atom.to_string(s.terminal_action)
          }
        end)
    }
  end

  defp approve_contact(contact, inbox, snapshot, version, actor) do
    CampaignContact.approve(contact, inbox.id, snapshot, version,
      actor: actor,
      authorize?: actor != nil
    )
  end

  defp schedule_step_one([], _inbox, _actor), do: {:ok, nil}

  defp schedule_step_one(drafts, inbox, actor) do
    case Enum.find(drafts, &(&1.step_position == 0)) do
      nil ->
        {:ok, nil}

      step1 ->
        with {:ok, slot} <-
               NextSlot.run(inbox, DateTime.utc_now(), step_position: 0, actor: actor),
             {:ok, _} <-
               OutboundEmail.schedule(step1, slot, inbox.id,
                 actor: actor,
                 authorize?: actor != nil
               ) do
          {:ok, slot}
        end
    end
  end

  defp approve_other_steps(drafts, actor) do
    drafts
    |> Enum.reject(&(&1.step_position == 0))
    |> Enum.each(fn e ->
      OutboundEmail.mark_approved(e, actor: actor, authorize?: actor != nil)
    end)

    {:ok, :ok}
  end

  defp maybe_bump_streak(campaign_id, drafts, actor) do
    if clean?(drafts) do
      with {:ok, campaign} <-
             Campaign.get(campaign_id, actor: actor, authorize?: actor != nil),
           {:ok, _} <- Campaign.bump_auto_approve_streak(campaign, actor: actor) do
        {:ok, :bumped}
      end
    else
      {:ok, :skipped}
    end
  end

  # Hard guard so a half-loaded UI (drafts still being generated, or
  # EmailWriter silently crashed) can't approve a contact into nothing.
  defp ensure_drafts_present([]), do: {:error, :no_drafts_to_approve}
  defp ensure_drafts_present([_ | _]), do: :ok

  defp clean?(drafts),
    do: Enum.all?(drafts, fn e -> is_nil(e.user_subject) and is_nil(e.user_body) end)
end
