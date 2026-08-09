defmodule Colt.Services.Admin.ClientProfile do
  @moduledoc """
  Everything the per-client admin page shows for one user: money lifetime and
  by month, the whole activation funnel with its drop-offs, every campaign,
  the resolved contact/company identity, and the activity signals that say
  whether they're actually using the product.

  Memoized for 24h per user; `refresh/1` clears one client.
  """

  use Memoize

  alias Colt.Accounts

  alias Colt.Resources.{
    ApiCall,
    Campaign,
    CampaignCompany,
    InboundEmail,
    OutboundEmail,
    RevenueEntry
  }

  @months_back 12
  @cache_ms 24 * 60 * 60 * 1000

  @campaign_loads [
    :total_count,
    :screened_count,
    :done_count,
    :sent_contacts_count,
    :replied_contacts_count,
    :interested_contacts_count,
    :last_contact_activity_at,
    :cost_usd
  ]

  @user_loads [
    :enriched_this_period_count,
    :screened_this_period_count,
    :email_accounts,
    :company,
    person: [:company]
  ]

  def run(user_id) when is_binary(user_id), do: cached(user_id, code_version())

  @doc "Drop one client's cached profile."
  def refresh(user_id), do: Memoize.invalidate(__MODULE__, :cached, [user_id, :_])

  # The cache lives in ETS and outlives a code reload, so a cached payload can
  # easily be a *shape* this module no longer speaks — the page then crashes on
  # a key that used to exist. Keying on the compiled module's own hash means any
  # edit here retires its own entries; stale ones just age out.
  defp code_version, do: __MODULE__.module_info(:md5)

  defmemop cached(user_id, _code_version), expires_in: @cache_ms do
    with {:ok, user} <- load_user(user_id),
         {:ok, campaigns} <- load_campaigns(user_id),
         {:ok, months} <- load_months(user_id),
         {:ok, entries} <- load_revenue_entries(user_id) do
      funnel = funnel(campaigns)
      money = money(months, campaigns)

      {:ok,
       %{
         user: user,
         identity: identity(user),
         campaigns: campaigns,
         funnel: funnel,
         months: months,
         money: money,
         entries: entries,
         usage: usage(user),
         activity: activity(user, campaigns),
         computed_at: DateTime.utc_now()
       }}
    end
  end

  defp load_user(user_id) do
    Accounts.get_user(user_id, load: @user_loads, authorize?: false)
  end

  defp load_campaigns(user_id) do
    {:ok, Campaign.list_for_user!(user_id, load: @campaign_loads, authorize?: false)}
  end

  defp load_revenue_entries(user_id) do
    {:ok, RevenueEntry.list_for_user!(user_id, authorize?: false)}
  end

  # --- identity -------------------------------------------------------------

  # Effective value = the admin's manual override, else what we hold about them
  # from our own enrichment. No mirrored "final" fields — resolved on read.
  defp identity(user) do
    person = user.person
    company = user.company || (person && person.company)

    # What our own data says, before any admin override.
    linked = %{
      full_name: person && person.name,
      phone: person && person.phone,
      company_name: company && company.name,
      company_reg_code: company && company.registry_code,
      country: company && market_label(company.market),
      website: company && company.website_url
    }

    # What the admin typed. Kept separate so the form can prefill the override
    # and only *hint* the linked value — saving never copies one into the other.
    override =
      Map.new(Map.keys(linked), fn key ->
        {key, user |> Map.get(key) |> blank_to_nil()}
      end)

    effective = Map.new(linked, fn {key, value} -> {key, override[key] || value} end)

    Map.merge(effective, %{
      person: person,
      company: company,
      title: person && person.title,
      notes: user.admin_notes,
      linked: linked,
      override: override,
      auto_matched?: auto_matched?(user, person)
    })
  end

  # Derived, not remembered: the link is an auto-match exactly when it points at
  # a contact carrying this user's own sign-up address. Survives remounts, and
  # goes away by itself if an admin relinks by hand.
  defp auto_matched?(_user, nil), do: false

  defp auto_matched?(user, person) do
    String.downcase(to_string(person.email || "")) == String.downcase(to_string(user.email))
  end

  defp blank_to_nil(value), do: if(present?(value), do: value)

  defp market_label(nil), do: nil
  defp market_label(market), do: market |> to_string() |> String.upcase()

  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: false

  # --- funnel ---------------------------------------------------------------

  # The activation funnel across every campaign, so "where do they get stuck"
  # is a single readable chain with the drop between each pair of steps.
  defp funnel(campaigns) do
    steps = [
      {:companies, "companies pulled", &(&1.total_count || 0)},
      {:screened, "screened", &(&1.screened_count || 0)},
      {:enriched, "enriched", &(&1.done_count || 0)},
      {:sent, "emailed", &(&1.sent_contacts_count || 0)},
      {:replied, "replied", &(&1.replied_contacts_count || 0)},
      {:interested, "interested", &(&1.interested_contacts_count || 0)}
    ]

    counts =
      Enum.map(steps, fn {key, label, fun} ->
        %{key: key, label: label, count: Enum.reduce(campaigns, 0, &(&2 + fun.(&1)))}
      end)

    drops =
      counts
      |> Enum.chunk_every(2, 1, :discard)
      |> Map.new(fn [prev, step] -> {step.key, drop_pct(prev.count, step.count)} end)

    steps = Enum.map(counts, &Map.put(&1, :drop, Map.get(drops, &1.key)))

    %{steps: steps, worst: worst_step(steps)}
  end

  defp drop_pct(0, _), do: nil
  defp drop_pct(prev, count), do: round((prev - count) / prev * 100)

  # Where they actually stall. `:screened` is skipped — the gap between
  # companies pulled and companies judged is the queue draining, not a problem,
  # and it would otherwise win every time.
  @stall_steps [:enriched, :sent, :replied, :interested]

  defp worst_step(steps) do
    steps
    |> Enum.filter(&(&1.key in @stall_steps and is_integer(&1.drop) and &1.drop > 0))
    |> Enum.max_by(& &1.drop, fn -> nil end)
    |> case do
      nil -> nil
      %{key: key} -> key
    end
  end

  # --- money ----------------------------------------------------------------

  # One row per month: the funnel as it happened that month, plus the money.
  # Every source is an owner-keyed rollup already, so this just narrows each to
  # this client and lines them up on a common axis.
  defp load_months(user_id) do
    cost = by_month(user_id, ApiCall.client_spending!(@months_back, authorize?: false), :cost_usd)

    revenue =
      by_month(
        user_id,
        RevenueEntry.client_revenue!(@months_back, authorize?: false),
        :amount_usd
      )

    screened =
      by_month(user_id, CampaignCompany.screened_by_month!(@months_back, authorize?: false))

    enriched =
      by_month(user_id, CampaignCompany.enriched_by_month!(@months_back, authorize?: false))

    emailed =
      by_month(user_id, OutboundEmail.contacts_emailed_by_month!(@months_back, authorize?: false))

    interested =
      by_month(user_id, InboundEmail.interested_by_month!(@months_back, authorize?: false))

    months =
      Enum.map(recent_months(@months_back), fn month ->
        rev = Map.get(revenue, month, Decimal.new(0))
        cst = Map.get(cost, month, Decimal.new(0))

        %{
          month: month,
          screened: Map.get(screened, month, 0),
          enriched: Map.get(enriched, month, 0),
          emailed: Map.get(emailed, month, 0),
          interested: Map.get(interested, month, 0),
          revenue: rev,
          cost: cst,
          profit: Decimal.sub(rev, cst)
        }
      end)

    {:ok, months}
  end

  defp by_month(user_id, rows), do: by_month(user_id, rows, :count)

  defp by_month(user_id, rows, key) do
    for row <- rows, row.user_id == user_id, into: %{} do
      {row.month, if(key == :count, do: row.count, else: to_decimal(Map.fetch!(row, key)))}
    end
  end

  # Chronological "YYYY-MM" list ending on the current month, so a client with
  # no activity still gets a full axis instead of an empty chart.
  defp recent_months(count) do
    today = Date.utc_today()
    now = today.year * 12 + (today.month - 1)

    for back <- (count - 1)..0//-1 do
      total = now - back
      month_string(div(total, 12), rem(total, 12) + 1)
    end
  end

  defp month_string(year, month) do
    "#{year}-" <> String.pad_leading(Integer.to_string(month), 2, "0")
  end

  defp money(months, campaigns) do
    revenue = sum(months, & &1.revenue)
    # Lifetime cost comes off the campaigns themselves, so it agrees with the
    # per-campaign cost column even outside the 12-month window.
    cost = Enum.reduce(campaigns, Decimal.new(0), &Decimal.add(&2, to_decimal(&1.cost_usd)))
    profit = Decimal.sub(revenue, cost)

    %{
      revenue: revenue,
      cost: cost,
      profit: profit,
      margin: margin(revenue, profit)
    }
  end

  defp margin(revenue, profit) do
    if Decimal.compare(revenue, 0) == :gt do
      profit
      |> Decimal.div(revenue)
      |> Decimal.mult(100)
      |> Decimal.round(0)
      |> Decimal.to_integer()
    end
  end

  # --- usage & activity -----------------------------------------------------

  defp usage(user) do
    capacity = user.monthly_contact_capacity || 0

    %{
      capacity: capacity,
      enriched: user.enriched_this_period_count,
      screening_capacity: capacity * 20,
      screened: user.screened_this_period_count,
      period_end: user.subscription_period_end,
      used_pct: pct(user.enriched_this_period_count, capacity)
    }
  end

  defp pct(_used, 0), do: nil
  defp pct(used, capacity), do: round(used / capacity * 100)

  defp activity(user, campaigns) do
    accounts = user.email_accounts || []

    %{
      last_campaign_at: campaigns |> Enum.map(& &1.updated_at) |> latest(),
      last_contact_at: campaigns |> Enum.map(& &1.last_contact_activity_at) |> latest(),
      email_accounts: length(accounts),
      email_accounts_ok: Enum.count(accounts, &sendable?/1),
      registered_days_ago: days_since(user.inserted_at)
    }
  end

  # Same definition as EmailAccount's :list_healthy — an inbox only counts if
  # it can actually send.
  defp sendable?(account),
    do: account.status == :healthy and not is_nil(account.nylas_grant_id)

  defp latest(stamps) do
    stamps
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_datetime/1)
    |> case do
      [] -> nil
      list -> Enum.max(list, DateTime)
    end
  end

  defp days_since(nil), do: nil

  defp days_since(stamp),
    do: DateTime.diff(DateTime.utc_now(), to_datetime(stamp), :second) |> div(86_400)

  # --- shared ---------------------------------------------------------------

  defp sum(rows, fun), do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(&2, fun.(&1)))

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(_), do: Decimal.new(0)

  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")
end
