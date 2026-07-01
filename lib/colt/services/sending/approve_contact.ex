defmodule Colt.Services.Sending.ApproveContact do
  @moduledoc """
  Move one CampaignContact from :pending_approval → :approved.

  Steps (run/3):
    1. Load contact + the template (sequence) it was written under + drafts.
    2. Apply pending user edits (subject, body per step).
    3. Pick sticky inbox.
    4. Snapshot the template's sequence (steps + delays + terminal).
    5. Update the contact: status, assigned_email_account, template, snapshot.
    6. Schedule step 1's Email via the §5.2 burst scheduler. Followups
       stay :approved until the send loop fires step N and schedules N+1.
    7. Mark the rest of the email drafts as :approved (no scheduled_at yet).

  The template is passed via `sequence_id:` in opts — the template the user
  was working in. Stamping it on the contact scopes future learning.
  """

  alias Colt.Resources.{CampaignContact, EmailAccount, OutboundEmail, Sequence}
  alias Colt.Services.Sending.{AssignInbox, NextSlot}

  def run(contact_id, edits, opts \\ []) when is_binary(contact_id) and is_map(edits) do
    actor = Keyword.get(opts, :actor)
    sequence_id = Keyword.get(opts, :sequence_id)

    with {:ok, contact} <- load_contact(contact_id, actor),
         {:ok, sequence} <- load_sequence(sequence_id, contact.campaign_id, actor),
         {:ok, drafts} <- load_drafts(contact, actor),
         :ok <- ensure_drafts_present(drafts),
         {:ok, drafts} <- apply_edits(drafts, edits, actor),
         {:ok, inbox} <- resolve_inbox(contact, actor),
         snapshot = build_snapshot(sequence),
         {:ok, contact} <- approve_contact(contact, inbox, sequence, snapshot, actor),
         {:ok, _} <- schedule_step_one(drafts, inbox, actor),
         {:ok, _} <- approve_other_steps(drafts, actor) do
      {:ok, %{contact_id: contact.id, inbox_id: inbox.id}}
    end
  end

  # Reuse the inbox the writer composed for (assigned at write time). Only fall
  # back to a fresh pick if the contact somehow reached approval unassigned.
  defp resolve_inbox(%{assigned_email_account_id: id}, actor) when is_binary(id),
    do: EmailAccount.get(id, actor: actor, authorize?: actor != nil)

  defp resolve_inbox(contact, actor), do: AssignInbox.run(contact.campaign_id, actor: actor)

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
    ooo_subject = Map.get(edits, "ooo_subject")
    bodies = Map.get(edits, "bodies", %{})

    updated =
      Enum.map(drafts, fn email ->
        body = Map.get(bodies, email.step_position) || Map.get(bodies, "#{email.step_position}")
        new_subject = subject_for(email, subject, ooo_subject)
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

  # The subject is shared across the linear sequence, but the OOO welcome-back
  # (position -1) keeps its own subject, taken from the approval payload's
  # `ooo_subject` (falling back to whatever was already saved on the draft).
  defp subject_for(%{step_position: -1} = email, _shared, ooo) when ooo in [nil, ""],
    do: email.user_subject

  defp subject_for(%{step_position: -1}, _shared, ooo), do: ooo
  defp subject_for(%{user_subject: s}, shared, _ooo) when shared in [nil, ""], do: s
  defp subject_for(_email, shared, _ooo), do: shared

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

  defp approve_contact(contact, inbox, sequence, snapshot, actor) do
    CampaignContact.approve(contact, inbox.id, sequence.id, snapshot, sequence.version,
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

  # Hard guard so a half-loaded UI (drafts still being generated, or
  # EmailWriter silently crashed) can't approve a contact into nothing.
  defp ensure_drafts_present([]), do: {:error, :no_drafts_to_approve}
  defp ensure_drafts_present([_ | _]), do: :ok
end
