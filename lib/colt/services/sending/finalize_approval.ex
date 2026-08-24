defmodule Colt.Services.Sending.FinalizeApproval do
  @moduledoc """
  Common tail of moving a CampaignContact from :pending_approval into the
  send machine: guard funnel membership, load + apply any pending edits,
  stamp the template + inbox, schedule step 1 via the burst scheduler, mark
  the rest of the drafts :approved, and record the sales-funnel status
  transition. Shared by ApproveContact (human click, edits already typed —
  pass them in) and AutoDraftAndApprove (cron, no edits — pass `%{}`,
  `auto_approved?: true`).

  The inbox is a parameter, not resolved here — both callers already know
  it via `StickyInbox.run/2` (the writer needed it resolved before it could
  compose), so re-resolving it here would just be a second sticky pick.
  """

  alias Colt.Resources.OutboundEmail
  alias Colt.Services.Sales.RecordStatusEvent
  alias Colt.Services.Sending.{EnsureInSendingFunnel, NextSlot}

  def run(contact, sequence, inbox, edits, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    auto_approved? = Keyword.get(opts, :auto_approved?, false)
    thread = contact.thread
    from = contact.status |> to_string() |> String.replace("_", " ")

    with {:ok, contact} <- EnsureInSendingFunnel.run(contact),
         {:ok, drafts} <- load_drafts(contact, actor),
         :ok <- ensure_drafts_present(drafts),
         {:ok, drafts} <- apply_edits(drafts, edits, actor),
         snapshot = build_snapshot(sequence),
         {:ok, contact} <- approve(contact, inbox, sequence, snapshot, auto_approved?, actor),
         {:ok, _} <- schedule_step_one(drafts, inbox, actor),
         {:ok, _} <- approve_other_steps(drafts, actor) do
      record_event(thread, from, actor)
      {:ok, %{contact_id: contact.id, inbox_id: inbox.id}}
    end
  end

  defp load_drafts(%{thread: nil}, _actor), do: {:ok, []}

  defp load_drafts(%{thread: %{id: tid}}, actor) do
    {:ok,
     OutboundEmail.list_for_thread!(tid, actor: actor, authorize?: actor != nil)
     |> Enum.filter(&(&1.status == :drafted))
     |> Enum.sort_by(& &1.step_position)}
  end

  # Hard guard so a half-loaded UI (drafts still being generated, or
  # EmailWriter silently crashed) can't approve a contact into nothing.
  defp ensure_drafts_present([]), do: {:error, :no_drafts_to_approve}
  defp ensure_drafts_present([_ | _]), do: :ok

  # edits = %{"subject" => "<single subject>",
  #           "bodies" => %{step_position => body_string}}
  # Auto-approve passes `%{}` — every draft comes back unchanged, a no-op.
  defp apply_edits(drafts, edits, actor) do
    subject = Map.get(edits, "subject")
    bodies = Map.get(edits, "bodies", %{})

    updated =
      Enum.map(drafts, fn email ->
        body = Map.get(bodies, email.step_position) || Map.get(bodies, "#{email.step_position}")
        new_subject = subject_for(email, subject)
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

  # One subject for the whole sequence — the opener, every follow-up and the
  # OOO welcome-back (position -1) all carry the same line, so the welcome-back
  # reads as part of the same conversation.
  defp subject_for(%{user_subject: s}, shared) when shared in [nil, ""], do: s
  defp subject_for(_email, shared), do: shared

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

  defp approve(contact, inbox, sequence, snapshot, auto_approved?, actor) do
    Ash.update(
      contact,
      %{
        assigned_email_account_id: inbox.id,
        sequence_id: sequence.id,
        sequence_snapshot: snapshot,
        sequence_version: sequence.version,
        auto_approved?: auto_approved?
      },
      action: :approve,
      actor: actor,
      authorize?: actor != nil
    )
  end

  defp schedule_step_one([], _, _), do: {:ok, nil}

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

  defp record_event(%{id: thread_id}, from, actor),
    do: RecordStatusEvent.run(thread_id, :send_status, from, "approved", actor: actor)

  defp record_event(_, _from, _actor), do: :ok
end
