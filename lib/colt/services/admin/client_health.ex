defmodule Colt.Services.Admin.ClientHealth do
  @moduledoc """
  Turns a client profile into the handful of sentences worth opening a call
  with: what's broken, what they're wasting, and what's going well.

  Pure — takes the map `Colt.Services.Admin.ClientProfile` returns and reads it.
  Ordered worst-first, because the first line is the one you actually say.
  """

  @stale_days 14

  def run(profile) do
    signals =
      [
        &billing/1,
        &never_started/1,
        &stuck_before_enrichment/1,
        &stuck_before_sending/1,
        &no_replies/1,
        &untouched_interested/1,
        &under_using_plan/1,
        &dormant/1,
        &unprofitable/1,
        &healthy/1
      ]
      |> Enum.map(& &1.(profile))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&tone_rank(&1.tone))

    {:ok, signals}
  end

  defp tone_rank(:bad), do: 0
  defp tone_rank(:warn), do: 1
  defp tone_rank(:good), do: 2

  # --- rules ----------------------------------------------------------------

  defp billing(%{user: %{subscription_status: :past_due}}),
    do: bad("payment is past due — sort the card out before anything else")

  defp billing(%{user: %{subscription_status: :canceled}}),
    do: bad("subscription cancelled — this is a win-back call")

  defp billing(_), do: nil

  defp never_started(%{campaigns: [], activity: %{registered_days_ago: days}}),
    do: bad("registered #{days_ago(days)} and never created a campaign")

  defp never_started(_), do: nil

  defp stuck_before_enrichment(%{campaigns: [_ | _]} = profile) do
    if step(profile, :enriched) == 0 do
      bad("#{count(profile.campaigns)} campaign(s), nothing enriched yet — stuck on setup")
    end
  end

  defp stuck_before_enrichment(_), do: nil

  defp stuck_before_sending(profile) do
    enriched = step(profile, :enriched)
    sent = step(profile, :sent)
    inboxes = profile.activity.email_accounts_ok

    cond do
      enriched == 0 or sent > 0 ->
        nil

      inboxes == 0 ->
        bad("#{enriched} contacts enriched, nothing sent — no working inbox connected")

      true ->
        bad("#{enriched} contacts enriched, nothing sent — they never pressed send")
    end
  end

  defp no_replies(profile) do
    sent = step(profile, :sent)

    if sent >= 50 and step(profile, :replied) == 0 do
      warn("#{sent} contacts emailed, zero replies — copy or targeting is off")
    end
  end

  defp untouched_interested(profile) do
    interested = step(profile, :interested)
    stale? = stale?(profile.activity.last_contact_at)

    if interested > 0 and stale? do
      warn("#{interested} interested lead(s) untouched for over #{@stale_days} days")
    end
  end

  defp under_using_plan(%{usage: %{used_pct: pct, capacity: capacity}} = profile)
       when is_integer(pct) and pct < 25 do
    if capacity > 0 and profile.user.subscription_status == :active do
      warn("using #{pct}% of a #{plan_price(profile)} plan this period")
    end
  end

  defp under_using_plan(_), do: nil

  defp dormant(%{activity: %{last_campaign_at: nil}}), do: nil

  defp dormant(%{activity: %{last_campaign_at: at}}) do
    if stale?(at), do: warn("dormant — nothing touched since #{date(at)}")
  end

  defp unprofitable(%{money: %{profit: profit}}) do
    if Decimal.compare(profit, 0) == :lt do
      warn("costing $#{abs_money(profit)} more than they've paid")
    end
  end

  defp healthy(profile) do
    profitable? = Decimal.compare(profile.money.profit, 0) == :gt

    if profitable? and step(profile, :replied) > 0 and profile.user.subscription_status == :active do
      good("sending, getting replies, and profitable — a reference customer")
    end
  end

  # --- helpers --------------------------------------------------------------

  defp step(%{funnel: %{steps: steps}}, key) do
    Enum.find_value(steps, 0, &if(&1.key == key, do: &1.count))
  end

  defp stale?(nil), do: true

  defp stale?(at),
    do: DateTime.diff(DateTime.utc_now(), at, :second) > @stale_days * 86_400

  defp plan_price(%{user: %{monthly_contact_capacity: capacity}}) do
    case Colt.Billing.monthly_eur(capacity) do
      0 -> "paid"
      eur -> "€#{eur}"
    end
  end

  defp count(list), do: length(list)

  defp days_ago(nil), do: "a while back"
  defp days_ago(0), do: "today"
  defp days_ago(1), do: "yesterday"
  defp days_ago(days), do: "#{days} days ago"

  defp date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")

  defp abs_money(decimal),
    do: decimal |> Decimal.abs() |> Decimal.round(2) |> Decimal.to_string(:normal)

  defp bad(text), do: %{tone: :bad, text: text}
  defp warn(text), do: %{tone: :warn, text: text}
  defp good(text), do: %{tone: :good, text: text}
end
