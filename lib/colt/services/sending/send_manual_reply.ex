defmodule Colt.Services.Sending.SendManualReply do
  @moduledoc """
  Send a user-composed reply on a Thread through Nylas, then persist
  it as an OutboundEmail with is_manual_reply: true. Threads via
  `reply_to_message_id` pointed at the most recent inbound (or last
  outbound) on the thread so providers stitch it into the conversation.
  """

  alias Colt.Nylas
  alias Colt.Resources.{InboundEmail, OutboundEmail, Thread}

  def run(thread_id, body_html, opts \\ []) when is_binary(thread_id) do
    actor = Keyword.get(opts, :actor)
    subject = Keyword.get(opts, :subject)

    with {:ok, thread} <- load_thread(thread_id, actor),
         {:ok, inbox} <- inbox(thread),
         {:ok, recipient} <- recipient(thread),
         {:ok, reply_to_id} <- last_message_id(thread_id),
         resolved_subject <- subject_or_re(subject, thread),
         {:ok, resp} <-
           Nylas.send_message(inbox,
             to: [recipient],
             subject: resolved_subject,
             body: body_html,
             reply_to_message_id: reply_to_id
           ),
         {:ok, email} <- persist(thread, inbox, resolved_subject, body_html, resp),
         {:ok, _} <- Thread.touch_activity(thread, DateTime.utc_now(), authorize?: false) do
      {:ok, email}
    end
  end

  defp load_thread(thread_id, _actor) do
    Ash.get(Thread, thread_id,
      load: [campaign_contact: [:person, :assigned_email_account]],
      authorize?: false
    )
  end

  defp inbox(%{campaign_contact: %{assigned_email_account: %_{} = inbox}}), do: {:ok, inbox}
  defp inbox(_), do: {:error, :no_assigned_inbox}

  defp recipient(%{campaign_contact: %{person: %{email: email}}}) when is_binary(email),
    do: {:ok, email}

  defp recipient(_), do: {:error, :no_recipient}

  defp last_message_id(thread_id) do
    inbound =
      case InboundEmail.list_for_thread(thread_id, authorize?: false) do
        {:ok, rows} -> rows |> Enum.sort_by(& &1.received_at, {:desc, DateTime}) |> List.first()
        _ -> nil
      end

    if inbound && inbound.nylas_message_id do
      {:ok, inbound.nylas_message_id}
    else
      outbound =
        case OutboundEmail.list_for_thread(thread_id, authorize?: false) do
          {:ok, rows} ->
            rows
            |> Enum.filter(&(&1.status == :sent and &1.nylas_message_id))
            |> Enum.sort_by(& &1.sent_at, {:desc, DateTime})
            |> List.first()

          _ ->
            nil
        end

      {:ok, outbound && outbound.nylas_message_id}
    end
  end

  defp subject_or_re(nil, thread), do: "re: " <> (last_subject(thread) || "")
  defp subject_or_re("", thread), do: "re: " <> (last_subject(thread) || "")
  defp subject_or_re(s, _) when is_binary(s), do: s

  defp last_subject(%{id: thread_id}) do
    with {:ok, rows} <- OutboundEmail.list_for_thread(thread_id, authorize?: false),
         %_{} = e <-
           rows
           |> Enum.filter(&(&1.status == :sent))
           |> Enum.sort_by(& &1.sent_at, {:desc, DateTime})
           |> List.first() do
      e.user_subject || e.ai_subject
    else
      _ -> nil
    end
  end

  defp persist(thread, inbox, subject, body, resp) do
    message_id = Map.get(resp, "id") || Map.get(resp, :id)

    nylas_thread_id =
      Map.get(resp, "thread_id") || Map.get(resp, :thread_id) || thread.nylas_thread_id

    sent_at = DateTime.utc_now()

    Ash.create(
      OutboundEmail,
      %{
        thread_id: thread.id,
        email_account_id: inbox.id,
        user_subject: subject,
        user_body: body,
        nylas_message_id: message_id,
        nylas_thread_id: nylas_thread_id,
        sent_at: sent_at
      },
      action: :create_manual_reply,
      authorize?: false
    )
  end
end
