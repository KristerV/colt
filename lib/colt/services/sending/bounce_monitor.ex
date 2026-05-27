defmodule Colt.Services.Sending.BounceMonitor do
  @moduledoc """
  Campaign-level bounce-rate guard (§8).

  After every bounce event (and as a safety net every 1000th send),
  recompute (bounce_count, sent_count) for the campaign. If
  sent_count ≥ 50 and bounce_count / sent_count > 5%, flip
  `Campaign.panic_switch_on = true` and broadcast a halt.

  Restoration is manual — the user toggles panic off after investigating.
  """

  require Logger

  alias Colt.Resources.{Campaign, CampaignContact, OutboundEmail}
  alias Colt.Services.Sending.Stats

  @sent_threshold 50
  @rate_threshold 0.05

  @doc "Returns `{:ok, %{paused?: bool, rate: float, sent: int, bounced: int}}`."
  def check(campaign_id) when is_binary(campaign_id) do
    counts = count_outbound(campaign_id)

    rate = ratio(counts.bounced, counts.sent)

    paused? =
      cond do
        counts.sent >= @sent_threshold and rate > @rate_threshold ->
          maybe_trip(campaign_id, rate)

        true ->
          false
      end

    {:ok, %{paused?: paused?, rate: rate, sent: counts.sent, bounced: counts.bounced}}
  end

  defp count_outbound(campaign_id) do
    contacts =
      case CampaignContact.list_for_campaign(campaign_id,
             load: [:thread],
             authorize?: false
           ) do
        {:ok, rows} -> rows
        _ -> []
      end

    outbound =
      Enum.flat_map(contacts, fn c ->
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

    %{
      sent: Enum.count(outbound, &(&1.status in [:sent, :bounced])),
      bounced: Enum.count(outbound, &(&1.status == :bounced))
    }
  end

  defp ratio(_, 0), do: 0.0
  defp ratio(num, denom), do: num / denom

  defp maybe_trip(campaign_id, rate) do
    case Campaign.get(campaign_id, authorize?: false) do
      {:ok, %{panic_switch_on: true}} ->
        true

      {:ok, campaign} ->
        Logger.warning(
          "BounceMonitor: tripping panic for campaign=#{campaign_id} rate=#{Float.round(rate * 100, 2)}%"
        )

        Campaign.set_panic(campaign, true, authorize?: false)
        Stats.invalidate(campaign_id)
        true

      _ ->
        false
    end
  end
end
