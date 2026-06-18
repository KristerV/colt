defmodule ColtWeb.Admin.ClientsLive do
  use ColtWeb, :live_view

  alias Colt.Accounts.User
  alias Colt.Resources.ApiCall
  alias ColtWeb.Admin.Summary

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  def mount(_params, _session, socket) do
    rows = build_rows()

    {:ok,
     socket
     |> assign(:rows, rows)
     |> assign(:total_users, length(rows))
     |> assign(:paying, Enum.count(rows, & &1.paid?))
     |> assign(:total_cost, total_cost(rows))}
  end

  # One row per user, enriched with lifetime API cost. Sorted by cost desc so the
  # heaviest clients surface first; ties break to newest registration.
  defp build_rows do
    totals =
      ApiCall.client_totals!(authorize?: false)
      |> Map.new(&{&1.user_id, &1})

    User
    |> Ash.read!(load: [:campaigns_count, :enriched_this_period_count], authorize?: false)
    |> Enum.map(fn user ->
      t = Map.get(totals, user.id, %{})

      %{
        id: user.id,
        email: to_string(user.email),
        is_admin: user.is_admin,
        registered: user.inserted_at,
        status: user.subscription_status,
        capacity: user.monthly_contact_capacity,
        used: user.enriched_this_period_count,
        period_end: user.subscription_period_end,
        campaigns: user.campaigns_count,
        cost: to_decimal(Map.get(t, :cost_usd, 0)),
        calls: Map.get(t, :calls, 0),
        last_call_at: Map.get(t, :last_call_at),
        paid?: User.paid?(user)
      }
    end)
    |> Enum.sort_by(
      &{Decimal.to_float(&1.cost), DateTime.to_unix(to_datetime(&1.registered))},
      :desc
    )
  end

  defp total_cost(rows) do
    Enum.reduce(rows, Decimal.new(0), &Decimal.add(&2, &1.cost))
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-10">
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />
        <h1 class="text-3xl font-semibold">Clients</h1>

        <div class="grid grid-cols-2 sm:grid-cols-3 gap-px bg-base-300 border border-base-300 rounded-sharp overflow-hidden md:max-w-2xl">
          <.stat label="users" value={@total_users} />
          <.stat label="paying" value={@paying} />
          <.stat label="API cost · lifetime" value={"$" <> format_money(@total_cost)} />
        </div>

        <div>
          <div class="text-xs uppercase tracking-wider opacity-60 font-mono mb-2">
            all users · sorted by lifetime API cost
          </div>
          <div class="overflow-x-auto">
            <table class="text-xs font-mono w-full min-w-[820px]">
              <thead class="opacity-60">
                <tr class="border-b border-base-300">
                  <th class="text-left py-1 pr-3">client</th>
                  <th class="text-left py-1 pr-3">registered</th>
                  <th class="text-left py-1 pr-3">status</th>
                  <th class="text-right py-1 pr-3">used / plan</th>
                  <th class="text-right py-1 pr-3">campaigns</th>
                  <th class="text-right py-1 pr-3">renews</th>
                  <th class="text-right py-1 pr-3">calls</th>
                  <th class="text-right py-1 pr-3">last active</th>
                  <th class="text-right py-1 pr-3">API cost</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={r <- @rows} class="border-b border-base-300/40">
                  <td class="py-1 pr-3 truncate max-w-[18rem]">
                    {r.email}
                    <span :if={r.is_admin} class="opacity-50">· admin</span>
                  </td>
                  <td class="py-1 pr-3 tabular-nums">{format_date(r.registered)}</td>
                  <td class="py-1 pr-3">
                    <span class={status_class(r.status)}>{r.status}</span>
                  </td>
                  <td class="py-1 pr-3 text-right tabular-nums">
                    {r.used} / {r.capacity}
                  </td>
                  <td class="py-1 pr-3 text-right tabular-nums">{r.campaigns}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">{format_date(r.period_end)}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">{r.calls}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">{format_date(r.last_call_at)}</td>
                  <td class="py-1 pr-3 text-right tabular-nums font-semibold">
                    ${format_money(r.cost)}
                  </td>
                </tr>
                <tr :if={@rows == []}>
                  <td colspan="9" class="py-2 opacity-60">no users yet</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div class="bg-base-200 p-4">
      <div class="text-xs uppercase tracking-wider opacity-60 font-mono">{@label}</div>
      <div class="font-serif text-4xl tabular-nums leading-none mt-2">{@value}</div>
    </div>
    """
  end

  defp status_class(:active), do: "text-success"
  defp status_class(:past_due), do: "text-warning"
  defp status_class(:canceled), do: "opacity-60 line-through"
  defp status_class(_), do: "opacity-60"

  defp format_date(nil), do: "—"
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")

  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(_), do: Decimal.new(0)

  defp format_money(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string(:normal)
  defp format_money(n) when is_number(n), do: n |> to_decimal() |> format_money()
  defp format_money(_), do: "0.00"
end
