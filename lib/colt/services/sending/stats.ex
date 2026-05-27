defmodule Colt.Services.Sending.Stats do
  @moduledoc """
  Funnel + headline metrics for the sending dashboard. Computed once per
  campaign and memoized for 15s. Invalidate on send/reply/bounce events
  via `Colt.Services.Sending.Stats.invalidate(campaign_id)`.

  Returns the same shape regardless of campaign state — empty buckets
  read 0.
  """

  use Memoize

  alias Colt.Resources.{CampaignContact, OutboundEmail}

  @doc """
  Compute the stats struct for a campaign. Memoized (15s).
  """
  defmemo for(campaign_id), expires_in: 15_000 do
    do_compute(campaign_id)
  end

  def invalidate(campaign_id) do
    Memoize.invalidate(__MODULE__, :for, [campaign_id])
  end

  defp do_compute(campaign_id) do
    contacts =
      case CampaignContact.list_for_campaign(campaign_id,
             load: [:thread],
             actor: nil,
             authorize?: false
           ) do
        {:ok, rows} -> rows
        _ -> []
      end

    outbound = list_campaign_outbound(contacts)

    sent = Enum.filter(outbound, &(&1.status == :sent))
    bounced = Enum.filter(outbound, &(&1.status == :bounced))

    opened = Enum.count(sent, &(&1.opens_count > 0))
    clicked = Enum.count(sent, &(&1.clicks_count > 0))

    %{
      total_contacts: length(contacts),
      total_sent: length(sent),
      total_bounced: length(bounced),
      total_opened: opened,
      total_clicked: clicked,
      bounce_rate: rate(length(bounced), length(sent)),
      reply_rate: reply_rate(contacts, length(sent)),
      interest_rate: interest_rate(contacts),
      open_rate: rate(opened, length(sent)),
      click_rate: rate(clicked, length(sent)),
      daily_avg: daily_avg(sent),
      buckets: bucket_counts(contacts, outbound)
    }
  end

  defp list_campaign_outbound(contacts) do
    contacts
    |> Enum.flat_map(fn c ->
      case c.thread do
        %{id: tid} ->
          case OutboundEmail.list_for_thread(tid, authorize?: false) do
            {:ok, rows} -> rows
            _ -> []
          end

        _ ->
          []
      end
    end)
  end

  defp rate(_, 0), do: 0.0
  defp rate(num, denom), do: Float.round(num / denom * 100, 1)

  defp reply_rate(contacts, sent_count) do
    replied = Enum.count(contacts, &(&1.status == :replied))
    rate(replied, sent_count)
  end

  defp interest_rate(contacts) do
    interested = Enum.count(contacts, &(&1.reply_category == :interested))
    not_interested = Enum.count(contacts, &(&1.reply_category == :not_interested))
    rate(interested, interested + not_interested)
  end

  defp daily_avg(sent) do
    cutoff = DateTime.add(DateTime.utc_now(), -7 * 86_400, :second)

    recent =
      sent
      |> Enum.count(fn e ->
        e.sent_at && DateTime.compare(e.sent_at, cutoff) == :gt
      end)

    Float.round(recent / 7.0, 1)
  end

  @doc """
  Compute the bucket each contact falls into. Used by the LiveView to
  filter the list when a tile is clicked.
  """
  def bucket_for(%CampaignContact{} = contact, sent_steps_by_contact) do
    case contact.status do
      :pending_approval ->
        :pending

      :bounced ->
        :bounced

      :failed ->
        :failed

      :no_reply ->
        :no_reply

      :call_ready ->
        :call_ready

      :replied ->
        case contact.reply_category do
          :interested -> :replied_interested
          :not_interested -> :replied_not_interested
          :ooo -> :replied_ooo
          _ -> :replied_other
        end

      s when s in [:approved, :sending] ->
        case Map.get(sent_steps_by_contact, contact.id) do
          nil -> :pending_send
          max_pos -> :"step_#{max_pos + 1}_sent"
        end
    end
  end

  defp bucket_counts(contacts, outbound) do
    sent_steps_by_contact =
      outbound
      |> Enum.filter(&(&1.status == :sent and &1.step_position != nil))
      |> Enum.group_by(& &1.thread_id, & &1.step_position)
      |> Enum.into(%{}, fn {tid, ps} -> {tid, Enum.max(ps)} end)

    # Map thread_id → contact_id. v1: one thread per contact.
    thread_to_contact =
      Enum.into(contacts, %{}, fn c -> {c.thread && c.thread.id, c.id} end)

    sent_by_contact =
      Enum.into(sent_steps_by_contact, %{}, fn {tid, max_pos} ->
        {Map.get(thread_to_contact, tid), max_pos}
      end)
      |> Map.delete(nil)

    contacts
    |> Enum.map(&bucket_for(&1, sent_by_contact))
    |> Enum.frequencies()
  end
end
