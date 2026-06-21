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
        <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">All <em>clients</em></h1>

        <div class="grid grid-cols-2 sm:grid-cols-3 gap-3 md:max-w-2xl">
          <.stat label="users" value={@total_users} />
          <.stat label="paying" value={@paying} />
          <.stat label="API cost · lifetime" value={"$" <> format_money(@total_cost)} />
        </div>

        <div>
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-2">
            all users · sorted by lifetime API cost
          </div>
          <div
            class="border border-border rounded-[11px] bg-card overflow-x-auto"
            style="box-shadow:var(--shadow-card)"
          >
            <table class="text-[12px] w-full min-w-[820px]">
              <thead>
                <tr class="border-b border-border bg-paperAlt text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55">
                  <th class="text-left px-3 py-2">client</th>
                  <th class="text-left px-3 py-2">registered</th>
                  <th class="text-left px-3 py-2">status</th>
                  <th class="text-right px-3 py-2">used / plan</th>
                  <th class="text-right px-3 py-2">campaigns</th>
                  <th class="text-right px-3 py-2">renews</th>
                  <th class="text-right px-3 py-2">calls</th>
                  <th class="text-right px-3 py-2">last active</th>
                  <th class="text-right px-3 py-2">API cost</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={r <- @rows} class="border-b border-border last:border-b-0 hover:bg-paperAlt">
                  <td class="px-3 py-1.5 truncate max-w-[18rem] text-ink">
                    {r.email}
                    <span :if={r.is_admin} class="text-ink40">· admin</span>
                  </td>
                  <td class="px-3 py-1.5 tabular-nums text-ink70">{format_date(r.registered)}</td>
                  <td class="px-3 py-1.5">
                    <span class={status_class(r.status)}>{r.status}</span>
                  </td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink70">
                    {r.used} / {r.capacity}
                  </td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink70">{r.campaigns}</td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink70">
                    {format_date(r.period_end)}
                  </td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink70">{r.calls}</td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink70">
                    {format_date(r.last_call_at)}
                  </td>
                  <td class="px-3 py-1.5 text-right tabular-nums font-semibold text-ink">
                    ${format_money(r.cost)}
                  </td>
                </tr>
                <tr :if={@rows == []}>
                  <td colspan="9" class="px-3 py-2 text-ink40">no users yet</td>
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
    <div class="bg-card border border-border rounded-[11px] p-4" style="box-shadow:var(--shadow)">
      <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55">{@label}</div>
      <div class="text-[27px] font-bold tabular-nums leading-none tracking-[-0.02em] text-ink mt-2">
        {@value}
      </div>
    </div>
    """
  end

  defp status_class(:active), do: "text-green font-medium"
  defp status_class(:past_due), do: "text-amber font-medium"
  defp status_class(:canceled), do: "text-ink40 line-through"
  defp status_class(_), do: "text-ink40"

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
