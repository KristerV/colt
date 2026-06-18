defmodule Colt.Jobs.AutoApproveCampaign do
  @moduledoc """
  Auto-approve driver for one campaign. Runs synchronously and serially so
  the slot accounting stays correct: each contact's step-1 row is persisted
  before the next slot is evaluated, so `NextSlot`'s today/tomorrow answer is
  always current. No race, no buffer to guess — approval rate == send capacity.

  Per campaign, for each healthy enrolled inbox, while that inbox still has an
  open slot **today**: pull the next contact (draining existing pending first,
  else minting one from the enriched pool) and draft + approve + schedule it
  in the current least-sent active variant. Stop when the inbox is full or the
  pool is exhausted.

  One job per campaign (Oban-unique on `campaign_id`), so there's never
  concurrency within a campaign — the only thing touching its pool. Enqueued
  hourly by `Colt.Jobs.AutoApproveDue`, and immediately when the user flips
  auto-approve on (so the schedule fills up while they watch).
  """

  use Oban.Worker,
    queue: :ai_writer,
    max_attempts: 1,
    unique: [period: 3600, keys: [:campaign_id], states: [:available, :scheduled, :executing]]

  require Logger

  alias Colt.Resources.{Campaign, CampaignContact, CampaignEmailAccount, Sequence}
  alias Colt.Resources.OutboundEmail
  alias Colt.Services.Sending.{AutoDraftAndApprove, NextSlot, PromoteOne}

  # Safety backstop: NextSlot is the real gate (it rolls to tomorrow once the
  # day's quota is hit), but if a start ever failed to persist a scheduled row
  # the loop could spin. Cap iterations per inbox well above any daily quota.
  @max_per_inbox 200

  def enqueue(campaign_id) when is_binary(campaign_id) do
    %{"campaign_id" => campaign_id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"campaign_id" => campaign_id}}) do
    with {:ok, campaign} <- Campaign.get(campaign_id, authorize?: false),
         true <- active?(campaign),
         true <- seeded_variant_exists?(campaign_id) do
      campaign_id
      |> healthy_inboxes()
      |> Enum.each(&fill_inbox(&1, campaign_id, 0))

      {:ok, :done}
    else
      false -> {:ok, :inactive}
      {:error, _} = err -> err
    end
  end

  defp active?(%{auto_approve_on?: true, panic_switch_on: false}), do: true
  defp active?(_), do: false

  # Walk one inbox until it's full for today or the pool runs dry.
  defp fill_inbox(account, campaign_id, guard) when guard >= @max_per_inbox do
    Logger.warning(
      "AutoApproveCampaign hit per-inbox guard (#{@max_per_inbox}) for account #{account.id}, campaign #{campaign_id}"
    )

    :ok
  end

  defp fill_inbox(account, campaign_id, guard) do
    now = DateTime.utc_now()

    case NextSlot.run(account, now, step_position: 0) do
      {:ok, slot} ->
        if slot_today?(slot, account.tz, now) do
          start_one(account, campaign_id, guard)
        else
          # NextSlot rolled to tomorrow → today's quota is spent for this inbox.
          :ok
        end

      {:error, _} ->
        :ok
    end
  end

  defp start_one(account, campaign_id, guard) do
    case next_contact(campaign_id) do
      {:ok, %CampaignContact{} = contact} ->
        case AutoDraftAndApprove.run(contact.id, inbox_id: account.id) do
          {:ok, _} -> fill_inbox(account, campaign_id, guard + 1)
          # Stop this inbox on a draft/schedule failure so a persistent error
          # can't spin the loop; the next tick retries from a clean slate.
          {:error, _} -> :ok
        end

      # Pool exhausted — nothing left to mint.
      {:ok, :none} ->
        :ok

      _ ->
        :ok
    end
  end

  # Drain existing :pending_approval contacts first (e.g. the bulk-promoted
  # backlog), then mint fresh ones from the enriched pool.
  defp next_contact(campaign_id) do
    case CampaignContact.next_pending(campaign_id, authorize?: false) do
      {:ok, %CampaignContact{} = contact} -> {:ok, contact}
      _ -> PromoteOne.run(campaign_id)
    end
  end

  defp slot_today?(slot_utc, tz, now_utc) do
    tz = tz || "Etc/UTC"

    Date.compare(
      slot_utc |> DateTime.shift_zone!(tz) |> DateTime.to_date(),
      now_utc |> DateTime.shift_zone!(tz) |> DateTime.to_date()
    ) == :eq
  end

  # At least one active variant that's been sent to someone (its voice has a
  # sample for the writer to learn from). Mirrors AutoDraftAndApprove's gate.
  defp seeded_variant_exists?(campaign_id) do
    campaign_id
    |> Sequence.list_enabled_for_campaign!(authorize?: false)
    |> Enum.any?(&seeded?/1)
  end

  defp seeded?(sequence) do
    case OutboundEmail.list_user_edited_for_sequence(sequence.id, 1, authorize?: false) do
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end

  defp healthy_inboxes(campaign_id) do
    campaign_id
    |> CampaignEmailAccount.list_for_campaign!(load: [:email_account], authorize?: false)
    |> Enum.reject(& &1.paused?)
    |> Enum.filter(fn r -> r.email_account && r.email_account.status == :healthy end)
    |> Enum.map(& &1.email_account)
  end
end
