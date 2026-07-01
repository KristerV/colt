defmodule Colt.Services.Sending.InjectOooWelcomeBack do
  @moduledoc """
  Admin-only (golden) feature. When an out-of-office auto-reply is detected and
  the contact's template carries a non-empty "welcome-back" email (the `:ooo`
  step at position `-1`, see `Colt.Resources.SequenceStep.ooo_position/0`), send
  that welcome-back at the prospect's return date + 3 days, then let the normal
  follow-ups resume behind it.

  This reuses the existing lazy-scheduling model rather than adding new state:

    1. The welcome-back content already lives on the thread as an approved,
       dormant `OutboundEmail` at `step_position -1` (the AI writer produced it
       per contact from the OOO few-shot pool).
    2. Push the currently-pending follow-up out to after the welcome-back (its
       own delay past `not_before`) — exactly what `DeferFollowup` does, just to
       a later bound. It stays the sequence's continuation pointer, so later
       steps still cascade off each actual send.
    3. Schedule the welcome-back at `not_before` (the shared return+3d / now+7d
       rule from `CategorizeReply.defer_not_before/1`), snapped to a burst slot.

  When the `-1` welcome-back sends, `SendOne` schedules no next step (it is not
  part of the linear flow) and the deferred follow-up carries the sequence on.

  Sent once per contact: if the `-1` row is already sent or scheduled, or no
  welcome-back was authored, returns `{:ok, :no_welcome_back}` and the caller
  falls back to the plain `DeferFollowup` path (unchanged legacy behavior).
  Returns `{:ok, {:injected, ooo_email_id, scheduled_at}}` on success.
  """

  require Logger

  alias Colt.Resources.{OutboundEmail, SequenceStep}
  alias Colt.Services.Sending.{EmailWriter, NextSlot}

  def run(thread_id, contact, %DateTime{} = not_before) when is_binary(thread_id) do
    with true <- ooo_step?(contact),
         {:ok, inbox, pending} <- target(thread_id, contact),
         {:ok, ooo_email} <- fetch_welcome_back(thread_id, inbox),
         # Defer the follow-up FIRST: if the welcome-back then fails to schedule
         # we've only deferred (safe fallback), never left two sends racing.
         {:ok, _} <- resume_followup(pending, contact, inbox, not_before),
         {:ok, slot} <- schedule_ooo(ooo_email, inbox, not_before) do
      {:ok, {:injected, ooo_email.id, slot}}
    else
      false -> {:ok, :no_welcome_back}
      {:error, :no_welcome_back} -> {:ok, :no_welcome_back}
      {:error, :no_inbox} -> {:ok, :no_welcome_back}
      {:error, reason} -> log_and_skip(reason)
    end
  end

  # OOO handling must never crash the categorizer; on an unexpected scheduling
  # error we log and fall back to the plain defer path.
  defp log_and_skip(reason) do
    Logger.warning("inject_ooo_welcome_back: #{inspect(reason)} — falling back to defer")
    {:ok, :no_welcome_back}
  end

  # An OOO welcome-back step exists on the contact's frozen sequence snapshot.
  defp ooo_step?(%{sequence_snapshot: %{"steps" => steps}}) when is_list(steps),
    do: Enum.any?(steps, &(Map.get(&1, "kind") == "ooo"))

  defp ooo_step?(_), do: false

  # Resolve the inbox and the follow-up to push out. The pending follow-up's
  # inbox is authoritative (mirrors DeferFollowup); when nothing is pending we
  # fall back to the contact's assigned inbox for the welcome-back send.
  defp target(thread_id, contact) do
    pending =
      case OutboundEmail.next_scheduled_for_thread(thread_id,
             load: [:email_account],
             authorize?: false,
             not_found_error?: false
           ) do
        {:ok, p} -> p
        _ -> nil
      end

    case inbox_for(pending, contact) do
      {:ok, inbox} -> {:ok, inbox, pending}
      err -> err
    end
  end

  defp inbox_for(%{email_account: %{} = acct}, _contact), do: {:ok, acct}

  defp inbox_for(_pending, contact) do
    case Ash.load(contact, [:assigned_email_account], authorize?: false) do
      {:ok, %{assigned_email_account: %{} = acct}} -> {:ok, acct}
      _ -> {:error, :no_inbox}
    end
  end

  # The dormant `-1` welcome-back row. Skipped (→ fall back to DeferFollowup)
  # when it is missing, already sent/scheduled (one-shot / in-flight), or its
  # effective body is empty — i.e. never actually authored beyond the seed.
  defp fetch_welcome_back(thread_id, inbox) do
    with {:ok, rows} <- OutboundEmail.list_for_thread(thread_id, authorize?: false),
         %{} = row <- Enum.find(rows, &(&1.step_position == SequenceStep.ooo_position())),
         false <- row.status in [:sent, :scheduled],
         true <- authored?(row, inbox) do
      {:ok, row}
    else
      _ -> {:error, :no_welcome_back}
    end
  end

  # Authored = the effective body has real content beyond the starter seed
  # (a blank hand-written card leaves only the signature seed / nothing).
  defp authored?(row, inbox) do
    body = row.user_body || row.ai_body
    seed = EmailWriter.starter_body(inbox)
    present?(body) and normalize(body) != normalize(seed)
  end

  defp present?(nil), do: false
  defp present?(s) when is_binary(s), do: String.trim(s) != ""

  defp normalize(nil), do: ""
  defp normalize(s) when is_binary(s), do: String.trim(s)

  # No pending follow-up ⇒ the welcome-back is the last thing sent; nothing to
  # resume. Otherwise defer it to its normal delay past the welcome-back.
  defp resume_followup(nil, _contact, _inbox, _not_before), do: {:ok, :no_pending}

  defp resume_followup(pending, contact, inbox, not_before) do
    delay = delay_for(contact, pending.step_position)
    after_welcome_back = DateTime.add(not_before, delay * 86_400, :second)

    with {:ok, slot} <-
           NextSlot.run(inbox, after_welcome_back, step_position: pending.step_position),
         {:ok, _} <- OutboundEmail.schedule(pending, slot, inbox.id, authorize?: false) do
      {:ok, :resumed}
    end
  end

  defp schedule_ooo(ooo_email, inbox, not_before) do
    with {:ok, slot} <-
           NextSlot.run(inbox, not_before, step_position: SequenceStep.ooo_position()),
         {:ok, _} <- OutboundEmail.schedule(ooo_email, slot, inbox.id, authorize?: false) do
      {:ok, slot}
    end
  end

  defp delay_for(%{sequence_snapshot: %{"steps" => steps}}, position) when is_list(steps) do
    case Enum.find(steps, &(Map.get(&1, "position") == position)) do
      %{"delay_days" => d} when is_integer(d) -> d
      _ -> 0
    end
  end

  defp delay_for(_contact, _position), do: 0
end
