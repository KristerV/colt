defmodule Colt.Services.Admin.ClientList do
  @moduledoc """
  Builds every row of the admin client list: registration, plan, the activation
  funnel (campaigns → with enriched → with sent → with interested) and lifetime
  money.

  The funnel is rolled up from **per-campaign** aggregates rather than
  user-level ones, so the list and the per-client page can never disagree —
  they read the same numbers.

  Expensive enough to be worth caching: memoized for 24h, `refresh/0` clears it.
  """

  use Memoize

  alias Colt.Accounts
  alias Colt.Resources.{ApiCall, Campaign, RevenueEntry}

  # Effectively "lifetime" for the money rollups, which take a month window.
  @lifetime_months 240
  @cache_ms 24 * 60 * 60 * 1000

  @campaign_loads [
    :total_count,
    :done_count,
    :sent_contacts_count,
    :interested_contacts_count,
    :cost_usd
  ]

  def run, do: cached(code_version())

  @doc "Drop the cache so the next `run/0` recomputes."
  def refresh, do: Memoize.invalidate(__MODULE__, :cached, [:_])

  # See ClientProfile: the ETS cache survives code reloads, so a row shape this
  # module no longer speaks can outlive it. Keying on the compiled module hash
  # makes any edit here retire its own entries.
  defp code_version, do: __MODULE__.module_info(:md5)

  defmemop cached(_code_version), expires_in: @cache_ms do
    with {:ok, users} <- load_users(),
         {:ok, by_owner} <- load_campaigns(),
         {:ok, cost} <- load_cost(),
         {:ok, revenue} <- load_revenue() do
      rows = Enum.map(users, &build_row(&1, by_owner, cost, revenue))

      {:ok,
       %{
         rows: rows,
         totals: totals(rows),
         computed_at: DateTime.utc_now()
       }}
    end
  end

  defp load_users, do: {:ok, Accounts.list_users!(load: [:email_accounts], authorize?: false)}

  defp load_campaigns do
    campaigns = Campaign.list_all_with_owner!(load: @campaign_loads, authorize?: false)
    {:ok, Enum.group_by(campaigns, & &1.owner_id)}
  end

  defp load_cost do
    {:ok, ApiCall.client_totals!(authorize?: false) |> Map.new(&{&1.user_id, &1})}
  end

  defp load_revenue do
    revenue =
      RevenueEntry.client_revenue!(@lifetime_months, authorize?: false)
      |> Enum.group_by(& &1.user_id)
      |> Map.new(fn {user_id, rows} ->
        {user_id, Enum.reduce(rows, Decimal.new(0), &Decimal.add(&2, to_decimal(&1.amount_usd)))}
      end)

    {:ok, revenue}
  end

  defp build_row(user, by_owner, cost, revenue) do
    campaigns = Map.get(by_owner, user.id, [])
    spend = Map.get(cost, user.id, %{})
    cost_usd = to_decimal(Map.get(spend, :cost_usd, 0))
    revenue_usd = Map.get(revenue, user.id, Decimal.new(0))

    %{
      id: user.id,
      email: to_string(user.email),
      is_admin: user.is_admin,
      registered: user.inserted_at,
      status: user.subscription_status,
      plan: Colt.Billing.plan_label(user.monthly_contact_capacity),
      plan_eur: Colt.Billing.monthly_eur(user.monthly_contact_capacity),
      capacity: user.monthly_contact_capacity,
      period_end: user.subscription_period_end,
      paid?: Colt.Accounts.User.paid?(user),
      campaigns: length(campaigns),
      # A client with contacts but no working inbox physically cannot send —
      # it's the step that most often explains a stalled funnel.
      inboxes: Enum.count(user.email_accounts || [], &(&1.status == :active)),
      with_enriched: Enum.count(campaigns, &(&1.done_count > 0)),
      with_sent: Enum.count(campaigns, &(&1.sent_contacts_count > 0)),
      with_interested: Enum.count(campaigns, &(&1.interested_contacts_count > 0)),
      revenue: revenue_usd,
      cost: cost_usd,
      profit: Decimal.sub(revenue_usd, cost_usd),
      last_active_at: last_active_at(campaigns, Map.get(spend, :last_call_at))
    }
  end

  # "Using the product" has no login trail, so the freshest of: their last
  # tracked API call and their most recently touched campaign.
  defp last_active_at(campaigns, last_call_at) do
    campaigns
    |> Enum.map(& &1.updated_at)
    |> then(&[last_call_at | &1])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_datetime/1)
    |> case do
      [] -> nil
      stamps -> Enum.max(stamps, DateTime)
    end
  end

  defp totals(rows) do
    %{
      users: length(rows),
      paying: Enum.count(rows, & &1.paid?),
      mrr_eur:
        rows |> Enum.filter(&(&1.status == :active)) |> Enum.map(& &1.plan_eur) |> Enum.sum(),
      revenue: sum(rows, & &1.revenue),
      cost: sum(rows, & &1.cost),
      profit: sum(rows, & &1.profit)
    }
  end

  defp sum(rows, fun), do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(&2, fun.(&1)))

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(_), do: Decimal.new(0)

  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")
end
