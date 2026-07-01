defmodule Colt.Services.Sending.SendOne do
  @moduledoc """
  Send a single scheduled OutboundEmail through Nylas, then schedule the
  next step in the contact's sequence snapshot (if any).

  Steps (run/1):

    1. Load email + thread + campaign_contact + person + campaign + inbox.
    2. 24h dedupe — raise on violation (per §5.4).
    3. Panic switch — campaign.panic_switch_on → `{:ok, :skipped_panic}`.
    4. Inbox health — EmailAccount.status != :healthy or
       CampaignEmailAccount.paused? → `{:ok, :skipped_inbox_paused}`.
    5. Compose payload (subject = user_? || ai_?, body likewise).
    6. `Colt.Nylas.send_message` — single attempt; Oban owns retry.
    7. Mark sent + store nylas ids.
    8. Schedule the next step's OutboundEmail (status :approved → :scheduled) using
       the burst scheduler, lower bound `sent_at + delay_days`.
    9. Broadcast `{:email_sent, …}` on `campaign:<id>`.
  """

  alias Colt.Nylas

  alias Colt.Resources.{
    CampaignContact,
    CampaignEmailAccount,
    OutboundEmail,
    Thread
  }

  alias Colt.Services.Sending.{Broadcast, NextSlot}

  @dedupe_window_hours 24

  def run(email_id) when is_binary(email_id) do
    with {:ok, ctx} <- load(email_id),
         :ok <- guard_already_sent(ctx),
         :ok <- check_dedupe(ctx),
         {:ok, next} <- proceed_or_skip(ctx) do
      {:ok, next}
    end
  end

  # Hard idempotency check. Oban retries the whole job on any post-Nylas
  # failure (e.g. mark_sent ok, but next-step scheduling errors). Without
  # this guard the retry would hit Nylas again and deliver a duplicate.
  defp guard_already_sent(%{email: %{status: :sent}}), do: {:ok, :already_sent}
  defp guard_already_sent(_), do: :ok

  # ── Load ─────────────────────────────────────────────────────────────

  defp load(email_id) do
    with {:ok, email} <-
           Ash.get(OutboundEmail, email_id,
             load: [
               thread: [campaign_contact: [:person, :campaign]],
               email_account: []
             ],
             authorize?: false
           ) do
      contact = email.thread && email.thread.campaign_contact
      campaign = contact && contact.campaign
      person = contact && contact.person
      inbox = email.email_account

      if email && contact && campaign && person && inbox do
        {:ok,
         %{
           email: email,
           contact: contact,
           campaign: campaign,
           person: person,
           inbox: inbox
         }}
      else
        {:error, :incomplete_email_context}
      end
    end
  end

  # ── 24h dedupe ──────────────────────────────────────────────────────

  defp check_dedupe(%{email: email, person: person, campaign: campaign}) do
    since = DateTime.utc_now() |> DateTime.add(-@dedupe_window_hours * 3600, :second)

    case OutboundEmail.recent_to_recipient(person.email, campaign.id, since, authorize?: false) do
      {:ok, rows} ->
        case Enum.reject(rows, &(&1.id == email.id)) do
          [] ->
            :ok

          [_ | _] ->
            raise "24h dedupe violation: #{person.email} in campaign #{campaign.id}"
        end

      {:error, reason} ->
        {:error, {:dedupe_lookup_failed, reason}}
    end
  end

  # ── Gate checks ─────────────────────────────────────────────────────

  defp proceed_or_skip(%{campaign: %{panic_switch_on: true}} = ctx) do
    Broadcast.skipped(ctx.campaign.id, ctx.email.id, ctx.contact.id, :panic)
    {:ok, :skipped_panic}
  end

  defp proceed_or_skip(%{inbox: %{status: status}} = ctx) when status != :healthy do
    Broadcast.skipped(ctx.campaign.id, ctx.email.id, ctx.contact.id, :inbox_unhealthy)
    {:ok, :skipped_inbox_paused}
  end

  defp proceed_or_skip(ctx) do
    with {:ok, pairing} <- pairing(ctx) do
      if pairing && pairing.paused? do
        Broadcast.skipped(ctx.campaign.id, ctx.email.id, ctx.contact.id, :inbox_paused)
        {:ok, :skipped_inbox_paused}
      else
        do_send(ctx)
      end
    end
  end

  defp pairing(%{campaign: campaign, inbox: inbox}) do
    case CampaignEmailAccount.get_pairing(campaign.id, inbox.id, authorize?: false) do
      {:ok, row} -> {:ok, row}
      {:error, _} -> {:ok, nil}
    end
  end

  # ── Real send ───────────────────────────────────────────────────────

  defp do_send(ctx) do
    %{email: email, person: person, inbox: inbox} = ctx
    subject = email.user_subject || email.ai_subject || ""
    body = email.user_body || email.ai_body || ""

    send_opts =
      [
        to: [person.email],
        subject: subject,
        body: plain_to_html(body)
      ]
      |> maybe_put(:tracking_options, tracking_options(ctx.campaign))

    case Nylas.send_message(inbox, send_opts) do
      {:ok, %{"id" => message_id} = resp} ->
        finalize_sent(ctx, message_id, resp["thread_id"])

      {:ok, %{id: message_id} = resp} ->
        finalize_sent(ctx, message_id, Map.get(resp, :thread_id))

      {:ok, other} ->
        {:error, {:unexpected_send_response, other}}

      {:error, reason} ->
        Broadcast.failed(ctx.campaign.id, email.id, ctx.contact.id, reason)
        {:error, reason}
    end
  end

  defp finalize_sent(ctx, message_id, thread_id) do
    sent_at = DateTime.utc_now()

    with {:ok, _} <-
           OutboundEmail.mark_sent(ctx.email, message_id, thread_id, sent_at, authorize?: false),
         {:ok, _} <- maybe_stamp_thread(ctx.email.thread_id, message_id, thread_id, sent_at),
         {:ok, next} <- schedule_next_step(ctx, sent_at) do
      Broadcast.sent(ctx.campaign.id, ctx.email.id, ctx.contact.id, ctx.email.step_position)
      maybe_bounce_safety_net(ctx.campaign.id)

      case next do
        {:scheduled, next_email_id, position} ->
          Broadcast.next_scheduled(ctx.campaign.id, next_email_id, ctx.contact.id, position)

        _ ->
          :ok
      end

      {:ok, :sent}
    end
  end

  # First send of a thread captures the Nylas thread id so subsequent
  # inbound polling can match replies back to it. Idempotent — only
  # stamps if currently nil.
  defp maybe_stamp_thread(_thread_id, _message_id, nil, _sent_at), do: {:ok, :no_thread_id}

  defp maybe_stamp_thread(thread_id, _message_id, nylas_thread_id, sent_at) do
    case Ash.get(Thread, thread_id, authorize?: false) do
      {:ok, %{nylas_thread_id: nil} = thread} ->
        with {:ok, t} <-
               Thread.set_nylas_thread_id(thread, nylas_thread_id, authorize?: false) do
          Thread.touch_activity(t, sent_at, authorize?: false)
        end

      {:ok, thread} ->
        Thread.touch_activity(thread, sent_at, authorize?: false)

      err ->
        err
    end
  end

  # ── Next step scheduling ────────────────────────────────────────────

  # Just sent an OOO welcome-back (position -1, see SequenceStep.ooo_position/0).
  # It's a one-off insertion, not part of the linear 0..N flow — the follow-up
  # that resumes was already rescheduled to after this send when the OOO reply
  # was categorized, so there's nothing to schedule here.
  defp schedule_next_step(%{email: %{step_position: -1}}, _sent_at), do: {:ok, :ooo_sent}

  defp schedule_next_step(ctx, sent_at) do
    snapshot = ctx.contact.sequence_snapshot || %{}
    steps = Map.get(snapshot, "steps") || []
    current_pos = ctx.email.step_position
    next_step = Enum.find(steps, fn s -> Map.get(s, "position") == current_pos + 1 end)

    case next_step do
      nil ->
        # No further step — either terminal or last email step.
        finalize_contact(ctx, snapshot, current_pos)

      %{"kind" => "terminal"} = step ->
        terminal(ctx, step)

      %{"delay_days" => delay} ->
        with {:ok, next_email} <- find_next_email(ctx, current_pos + 1),
             not_before <- DateTime.add(sent_at, (delay || 0) * 86_400, :second),
             {:ok, slot} <-
               NextSlot.run(ctx.inbox, not_before, step_position: current_pos + 1),
             {:ok, _} <- OutboundEmail.schedule(next_email, slot, ctx.inbox.id, authorize?: false) do
          {:ok, {:scheduled, next_email.id, current_pos + 1}}
        end
    end
  end

  defp find_next_email(ctx, position) do
    case OutboundEmail.list_for_thread(ctx.email.thread_id, authorize?: false) do
      {:ok, rows} ->
        case Enum.find(rows, &(&1.step_position == position)) do
          nil -> {:error, {:no_email_for_step, position}}
          row -> {:ok, row}
        end

      err ->
        err
    end
  end

  defp terminal(ctx, _step) do
    {:ok, _} = CampaignContact.set_status(ctx.contact, :no_reply, authorize?: false)
    {:ok, :terminal}
  end

  defp finalize_contact(ctx, _snapshot, _current_pos) do
    {:ok, _} = CampaignContact.set_status(ctx.contact, :no_reply, authorize?: false)
    {:ok, :no_more_steps}
  end

  # Safety net (§8): every 1000th send across the campaign, recompute
  # bounce metrics in case we missed a bounce event upstream. Cheap —
  # the BounceMonitor early-returns when sent_count < 50.
  defp maybe_bounce_safety_net(campaign_id) do
    if :rand.uniform(1000) == 1 do
      Colt.Services.Sending.BounceMonitor.check(campaign_id)
    end

    :ok
  end

  # Nylas v3's `body` field is HTML. The AI writes plain text, so escape
  # HTML special chars and convert newlines to <br>. Bare links (http/https)
  # already came through as anchors because Nylas-side rendering wraps URLs;
  # keeping the rest as escaped text preserves intent.
  defp plain_to_html(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace("\n", "<br>\n")
  end

  defp plain_to_html(_), do: ""

  # Build Nylas tracking_options if the campaign has opens/clicks on AND
  # a site-wide tracking domain is configured. Without a domain Nylas
  # will reject tracking or fall back to its bare cname — which we don't
  # want, per docs/email-sending.md §12.
  defp tracking_options(%{tracking_opens?: false, tracking_clicks?: false}), do: nil

  defp tracking_options(%{} = campaign) do
    case Colt.AppSettings.tracking_domain() do
      nil ->
        nil

      _domain ->
        %{
          opens: campaign.tracking_opens? == true,
          links: campaign.tracking_clicks? == true,
          tracking_label: "campaign:#{campaign.id}"
        }
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
