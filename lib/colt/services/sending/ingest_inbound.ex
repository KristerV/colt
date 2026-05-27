defmodule Colt.Services.Sending.IngestInbound do
  @moduledoc """
  Ingest one inbound Nylas message into a Thread + InboundEmail row, or
  route a bounce notification to the matching OutboundEmail. Idempotent
  — re-ingesting the same `nylas_message_id` upserts on the unique
  identity and no-ops downstream because we early-exit when we already
  have the row.

  Steps (run/2):

    1. Skip if we already have this `nylas_message_id`.
    2. Fetch the full message from Nylas.
    3. Bounce? → §7.4 — find the matching OutboundEmail, flag bounced.
       (Bounces never become InboundEmail rows.)
    4. Thread match by `nylas_thread_id`.
    5. Else cross-domain match: same inbox + sender domain matches a
       live contact's address. Attach with `auto_attached? = true`.
    6. Else orphan — log and stop (§7.2.5).
    7. Insert the InboundEmail, touch Thread.last_activity_at, enqueue
       CategorizeReply.
  """

  require Logger

  alias Colt.Nylas

  alias Colt.Resources.{
    CampaignContact,
    EmailAccount,
    InboundEmail,
    OutboundEmail,
    Thread
  }

  alias Colt.Services.Sending.Broadcast

  def run(email_account_id, nylas_message_id)
      when is_binary(email_account_id) and is_binary(nylas_message_id) do
    with {:ok, :new} <- guard_already_ingested(nylas_message_id),
         {:ok, account} <- Ash.get(EmailAccount, email_account_id, authorize?: false),
         {:ok, raw} <- Nylas.get_message(account, nylas_message_id),
         msg <- normalize(raw),
         {:ok, result} <- route(account, msg) do
      {:ok, result}
    end
  end

  # ── Idempotency ─────────────────────────────────────────────────────

  defp guard_already_ingested(message_id) do
    case InboundEmail.find_by_nylas_message(message_id, authorize?: false) do
      {:ok, nil} -> {:ok, :new}
      {:ok, %InboundEmail{}} -> {:ok, :already_ingested}
      _ -> {:ok, :new}
    end
  end

  # ── Routing ─────────────────────────────────────────────────────────

  defp route(account, %{bounce?: true} = msg), do: route_bounce(account, msg)

  defp route(account, msg) do
    if from_inbox?(account, msg) do
      # Our own send echoed back via Sent/All Mail — already represented
      # as the outbound row, nothing to insert.
      {:ok, :own_send_echo}
    else
      match_thread(account, msg)
    end
  end

  defp match_thread(account, msg) do
    case msg.nylas_thread_id &&
           Thread.find_by_nylas_thread_id(msg.nylas_thread_id, authorize?: false) do
      {:ok, %Thread{} = thread} -> attach_to_thread(account, thread, msg, false)
      _ -> domain_fallback(account, msg)
    end
  end

  defp domain_fallback(_account, %{from_domain: nil}), do: {:ok, :orphan_no_domain}

  defp domain_fallback(account, msg) do
    case CampaignContact.find_active_in_inbox_by_domain(account.id, msg.from_domain,
           load: [:thread],
           authorize?: false
         ) do
      {:ok, %CampaignContact{thread: %Thread{} = thread}} ->
        attach_to_thread(account, thread, msg, true)

      _ ->
        Logger.info("ingest_inbound: orphan msg=#{msg.nylas_message_id} from=#{msg.from_address}")

        {:ok, :orphan}
    end
  end

  # ── Attachment ──────────────────────────────────────────────────────

  defp attach_to_thread(account, thread, msg, auto_attached?) do
    with {:ok, inbound} <-
           InboundEmail.create_inbound(
             thread.id,
             account.id,
             msg.from_address,
             msg.subject,
             msg.body,
             msg.nylas_message_id,
             msg.nylas_thread_id,
             msg.received_at,
             auto_attached?,
             authorize?: false
           ),
         {:ok, _} <- maybe_stamp_thread_id(thread, msg.nylas_thread_id),
         {:ok, _} <- Thread.touch_activity(thread, msg.received_at, authorize?: false) do
      campaign_id = campaign_id_from_thread(thread)
      Broadcast.inbound(campaign_id, inbound.id, thread.campaign_contact_id)
      Colt.Jobs.CategorizeReply.enqueue(inbound.id)
      {:ok, {:attached, inbound.id, auto_attached?}}
    end
  end

  defp maybe_stamp_thread_id(%Thread{nylas_thread_id: nil} = thread, nylas_thread_id)
       when is_binary(nylas_thread_id) do
    Thread.set_nylas_thread_id(thread, nylas_thread_id, authorize?: false)
  end

  defp maybe_stamp_thread_id(thread, _), do: {:ok, thread}

  defp campaign_id_from_thread(%Thread{} = thread) do
    case Ash.load(thread, [campaign_contact: [:campaign]], authorize?: false) do
      {:ok, %Thread{campaign_contact: %{campaign: %{id: id}}}} -> id
      _ -> nil
    end
  end

  # ── Bounces ─────────────────────────────────────────────────────────

  defp route_bounce(account, msg) do
    case OutboundEmail.find_to_recipient_in_inbox(account.id, msg.bounced_recipient,
           load: [thread: [campaign_contact: [:campaign]]],
           authorize?: false
         ) do
      {:ok, %OutboundEmail{} = outbound} ->
        with {:ok, _} <-
               OutboundEmail.mark_bounced(outbound, msg.bounce_reason, authorize?: false),
             {:ok, _} <- maybe_mark_contact_bounced(outbound) do
          Broadcast.failed(
            campaign_id_from_outbound(outbound),
            outbound.id,
            outbound.thread && outbound.thread.campaign_contact_id,
            {:bounced, msg.bounce_reason}
          )

          {:ok, {:bounced, outbound.id}}
        end

      _ ->
        Logger.info("ingest_inbound: bounce for unknown recipient=#{msg.bounced_recipient}")
        {:ok, :bounce_no_match}
    end
  end

  defp maybe_mark_contact_bounced(%OutboundEmail{
         thread: %Thread{campaign_contact: %CampaignContact{} = contact}
       }) do
    CampaignContact.mark_bounced(contact, authorize?: false)
  end

  defp maybe_mark_contact_bounced(_), do: {:ok, :no_contact}

  defp campaign_id_from_outbound(%OutboundEmail{
         thread: %Thread{campaign_contact: %{campaign_id: id}}
       }),
       do: id

  defp campaign_id_from_outbound(_), do: nil

  # ── Normalization ───────────────────────────────────────────────────

  # Nylas v3 message shape (relevant fields):
  #   id, thread_id, subject, body, snippet,
  #   from: [%{"email" => , "name" => }],
  #   to:   [%{"email" => , "name" => }],
  #   date: unix seconds,
  #   tracking.bounced — see §7.4 (verify field at implementation time).
  defp normalize(raw) do
    from_address = first_address(Map.get(raw, "from"))
    bounce? = bounce?(raw, from_address)

    %{
      nylas_message_id: Map.get(raw, "id"),
      nylas_thread_id: Map.get(raw, "thread_id"),
      subject: Map.get(raw, "subject") || "",
      body: Map.get(raw, "body") || Map.get(raw, "snippet") || "",
      from_address: from_address,
      from_domain: domain_of(from_address),
      received_at: unix_to_dt(Map.get(raw, "date")),
      bounce?: bounce?,
      bounced_recipient: bounced_recipient(raw),
      bounce_reason: bounce_reason(raw)
    }
  end

  defp first_address([%{"email" => email} | _]) when is_binary(email), do: String.downcase(email)
  defp first_address(_), do: nil

  defp domain_of(nil), do: nil

  defp domain_of(email) when is_binary(email) do
    case String.split(email, "@", parts: 2) do
      [_, domain] -> String.downcase(domain)
      _ -> nil
    end
  end

  defp unix_to_dt(nil), do: DateTime.utc_now()

  defp unix_to_dt(secs) when is_integer(secs) do
    case DateTime.from_unix(secs, :second) do
      {:ok, dt} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp unix_to_dt(_), do: DateTime.utc_now()

  defp bounce?(raw, from_address) do
    tracking_flag?(raw) or mailer_daemon?(from_address)
  end

  defp tracking_flag?(raw) do
    case get_in(raw, ["tracking", "bounced"]) do
      true -> true
      _ -> false
    end
  end

  defp mailer_daemon?(nil), do: false

  defp mailer_daemon?(email) do
    String.starts_with?(email, "mailer-daemon@") or
      String.starts_with?(email, "postmaster@")
  end

  defp bounced_recipient(raw) do
    case get_in(raw, ["tracking", "bounced_recipient"]) do
      r when is_binary(r) ->
        String.downcase(r)

      _ ->
        case extract_original_recipients(raw) do
          [recipient | _] -> recipient
          _ -> nil
        end
    end
  end

  defp extract_original_recipients(raw) do
    body = Map.get(raw, "body") || Map.get(raw, "snippet") || ""

    Regex.scan(~r/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/, body)
    |> List.flatten()
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&String.starts_with?(&1, ["mailer-daemon@", "postmaster@"]))
  end

  defp bounce_reason(raw) do
    Map.get(raw, "subject") || "bounced"
  end

  defp from_inbox?(account, %{from_address: from}) when is_binary(from) do
    account.address && String.downcase(account.address) == from
  end

  defp from_inbox?(_, _), do: false
end
