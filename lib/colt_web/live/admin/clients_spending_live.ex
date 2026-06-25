defmodule ColtWeb.Admin.ClientsSpendingLive do
  use ColtWeb, :live_view

  alias Colt.Accounts
  alias Colt.Resources.{ApiCall, CampaignCompany, RevenueEntry}
  alias Colt.Services.Billing.RevenueSync
  alias ColtWeb.Admin.Summary
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  @months_back 12

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:open_client, nil)
     |> assign(:entries, [])
     |> assign(:form, new_form())
     |> load_data()}
  end

  # --- events ---------------------------------------------------------------

  def handle_event("open_client", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:open_client, id) |> assign(:entries, entries_for(id))}
  end

  def handle_event("close_client", _params, socket) do
    {:noreply, assign(socket, open_client: nil, entries: [], form: new_form())}
  end

  def handle_event("add_revenue", %{"revenue" => params}, socket) do
    user_id = socket.assigns.open_client

    attrs = %{
      user_id: user_id,
      month: params["month"],
      amount_usd: params["amount_usd"],
      source: params["source"],
      note: blank_to_nil(params["note"])
    }

    case RevenueEntry.record_manual(attrs, authorize?: false) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Revenue recorded")
         |> assign(:form, new_form())
         |> assign(:entries, entries_for(user_id))
         |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record revenue — check the values")}
    end
  end

  def handle_event("delete_revenue", %{"id" => id}, socket) do
    user_id = socket.assigns.open_client

    with {:ok, entry} <- RevenueEntry.get_by_id(id, authorize?: false),
         :ok <- RevenueEntry.delete(entry, authorize?: false) do
      {:noreply, socket |> assign(:entries, entries_for(user_id)) |> load_data()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("sync_stripe", _params, socket) do
    case RevenueSync.run() do
      {:ok, %{entries: n, clients: c}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Synced #{n} invoices across #{c} Stripe clients")
         |> load_data()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Stripe sync failed: #{inspect(reason)}")}
    end
  end

  # --- data -----------------------------------------------------------------

  defp load_data(socket) do
    cost_rows = ApiCall.client_spending!(@months_back, authorize?: false)
    {:ok, rev_rows} = RevenueEntry.client_revenue(@months_back, authorize?: false)
    {:ok, credit_rows} = CampaignCompany.enriched_by_month(@months_back, authorize?: false)
    users = Accounts.list_users!(load: [:enriched_this_period_count], authorize?: false)

    # Most recent @months_back months, oldest-first so the table reads
    # left→right with the newest month on the right.
    months =
      (Enum.map(cost_rows, & &1.month) ++ Enum.map(rev_rows, & &1.month))
      |> Enum.uniq()
      |> Enum.sort(:desc)
      |> Enum.take(@months_back)
      |> Enum.reverse()

    cost_um = sum_by_user_month(cost_rows, :cost_usd)
    rev_um = sum_by_user_month(rev_rows, :amount_usd)
    credits_um = Map.new(credit_rows, &{{&1.user_id, &1.month}, &1.count})
    meta = Map.new(users, &{&1.id, user_meta(&1)})
    email_from_cost = Map.new(cost_rows, &{&1.user_id, to_string(&1.email)})

    clients = build_clients(cost_um, rev_um, meta, email_from_cost, months)
    current_month = current_ym()

    socket
    |> assign(:months, months)
    |> assign(:clients, clients)
    |> assign(:cost_um, cost_um)
    |> assign(:rev_um, rev_um)
    |> assign(:credits_um, credits_um)
    |> assign(:meta, meta)
    |> assign(:current_month, current_month)
    |> assign(:current_profit, month_profit(clients, current_month, cost_um, rev_um))
  end

  defp build_clients(cost_um, rev_um, meta, email_from_cost, months) do
    user_ids =
      (Map.keys(cost_um) ++ Map.keys(rev_um))
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()

    user_ids
    |> Enum.map(fn id ->
      cost = sum_over_months(cost_um, id, months)
      revenue = sum_over_months(rev_um, id, months)
      m = Map.get(meta, id, %{})

      %{
        user_id: id,
        email: Map.get(m, :email) || Map.get(email_from_cost, id) || "—",
        cost: cost,
        revenue: revenue,
        profit: Decimal.sub(revenue, cost),
        by_month: month_profits(rev_um, cost_um, id, months),
        capacity: Map.get(m, :capacity, 0),
        enriched: Map.get(m, :enriched, 0),
        status: Map.get(m, :status, :none)
      }
    end)
    |> Enum.sort_by(& &1.profit, &(Decimal.compare(&1, &2) != :lt))
  end

  defp entries_for(user_id), do: RevenueEntry.list_for_user!(user_id, authorize?: false)

  defp user_meta(user) do
    %{
      email: to_string(user.email),
      capacity: user.monthly_contact_capacity,
      enriched: user.enriched_this_period_count,
      status: user.subscription_status
    }
  end

  # --- render ---------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />

        <div class="flex items-center justify-between gap-3">
          <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">
            Client <em>profit</em>
          </h1>
          <button
            type="button"
            class="text-[12px] font-medium text-accent hover:underline cursor-pointer flex items-center gap-1.5"
            phx-click="sync_stripe"
          >
            <Liid.icon name="refresh" size={13} /> Sync Stripe revenue
          </button>
        </div>

        <div
          class="bg-card border border-border rounded-[11px] md:max-w-md p-5 md:p-6"
          style="box-shadow:var(--shadow-card)"
        >
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55">
            profit this month · {@current_month}
          </div>
          <div class={[
            "text-[56px] font-bold tabular-nums leading-none tracking-[-0.02em] mt-2",
            profit_color(@current_profit)
          ]}>
            {format_signed(@current_profit)}
          </div>
          <div class="text-[13px] text-ink55 mt-2">revenue − API cost</div>
        </div>

        <div>
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-2">
            per client · last {length(@months)} months · click a row for detail
          </div>
          <div
            class="border border-border rounded-[11px] bg-card overflow-x-auto"
            style="box-shadow:var(--shadow-card)"
          >
            <table class="text-[12px] w-full min-w-[640px]">
              <thead>
                <tr class="border-b border-border bg-paperAlt text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55">
                  <th class="text-left px-3 py-2">client</th>
                  <th :for={m <- @months} class="text-right px-3 py-2 tabular-nums">{m}</th>
                  <th class="text-right px-3 py-2">profit</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={c <- @clients}
                  class="border-b border-border last:border-b-0 cursor-pointer hover:bg-paperAlt"
                  phx-click="open_client"
                  phx-value-id={c.user_id}
                >
                  <td class="px-3 py-2 truncate max-w-[18rem] text-ink">{c.email}</td>
                  <td :for={m <- @months} class="px-3 py-2 text-right tabular-nums">
                    <.profit_cell value={Map.get(c.by_month, m, :empty)} />
                  </td>
                  <td class={[
                    "px-3 py-2 text-right tabular-nums font-semibold",
                    profit_color(c.profit)
                  ]}>
                    {format_signed(c.profit)}
                  </td>
                </tr>
                <tr :if={@clients == []}>
                  <td colspan={length(@months) + 2} class="px-3 py-2 text-ink40">
                    no client activity in this period yet
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <.client_modal
        :if={@open_client}
        client={Enum.find(@clients, &(&1.user_id == @open_client))}
        months={@months}
        cost_um={@cost_um}
        rev_um={@rev_um}
        credits_um={@credits_um}
        entries={@entries}
        form={@form}
        user_id={@open_client}
      />
    </Layouts.app>
    """
  end

  defp client_modal(%{client: nil} = assigns), do: ~H""

  defp client_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
      style="background: rgba(20,18,14,0.45); backdrop-filter: blur(2px);"
    >
      <div
        class="bg-card border border-border rounded-[11px] w-full max-w-[760px] my-auto px-6 py-7 md:px-8 md:pt-8 md:pb-7"
        style="box-shadow: 0 24px 80px rgba(0,0,0,0.18);"
        phx-click-away="close_client"
        phx-window-keydown="close_client"
        phx-key="escape"
      >
        <div class="flex justify-between items-start gap-3 mb-5">
          <div class="min-w-0">
            <div class="text-[10px] font-semibold tracking-[0.08em] uppercase text-ink55 mb-1.5">
              client
            </div>
            <h2 class="font-semibold text-[22px] md:text-[24px] leading-[1.15] tracking-[-0.02em] text-ink m-0 truncate">
              {@client.email}
            </h2>
          </div>
          <button
            type="button"
            class="w-6 h-6 flex items-center justify-center cursor-pointer"
            phx-click="close_client"
          >
            <Liid.icon name="x" size={14} />
          </button>
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
          <.stat label="revenue" value={"$" <> format_usd(@client.revenue)} />
          <.stat label="API cost" value={"$" <> format_cost(@client.cost)} />
          <.stat
            label="profit"
            value={format_signed(@client.profit)}
            class={profit_color(@client.profit)}
          />
          <.stat label="margin" value={margin(@client)} />
        </div>

        <div class="mb-6">
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-1.5">
            credit usage · this period
          </div>
          <div class="border border-border rounded-[8px] bg-paperAlt px-4 py-3 text-[13px] text-ink70 flex items-center gap-2">
            <span class="tabular-nums font-semibold text-ink">{@client.enriched}</span>
            <span>/ {@client.capacity} contacts enriched</span>
            <span class="ml-auto text-[11px] text-ink55">{@client.status}</span>
          </div>
        </div>

        <div class="mb-6">
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-1.5">
            by month
          </div>
          <div class="border border-border rounded-[8px] overflow-hidden">
            <div class="grid grid-cols-5 px-3 py-1.5 bg-paperAlt text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55">
              <span>month</span>
              <span class="text-right">credits</span>
              <span class="text-right">revenue</span>
              <span class="text-right">cost</span>
              <span class="text-right">profit</span>
            </div>
            <div
              :for={m <- Enum.reverse(@months)}
              class="grid grid-cols-5 px-3 py-1.5 border-t border-border text-[12px]"
            >
              <span class="tabular-nums text-ink">{m}</span>
              <span class="text-right tabular-nums text-ink70">
                {Map.get(@credits_um, {@user_id, m}, 0)}
              </span>
              <span class="text-right tabular-nums text-ink70">
                ${format_usd(cell(@rev_um, @user_id, m))}
              </span>
              <span class="text-right tabular-nums text-ink70">
                ${format_cost(cell(@cost_um, @user_id, m))}
              </span>
              <span class={[
                "text-right tabular-nums",
                profit_color(month_cell_profit(@rev_um, @cost_um, @user_id, m))
              ]}>
                {format_signed(month_cell_profit(@rev_um, @cost_um, @user_id, m))}
              </span>
            </div>
          </div>
        </div>

        <div class="mb-6">
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-1.5">
            revenue entries
          </div>
          <div class="space-y-1">
            <div
              :for={e <- @entries}
              class="flex items-center gap-2 border border-border rounded-[8px] px-3 py-1.5 text-[12px]"
            >
              <span class="tabular-nums text-ink">{e.month}</span>
              <span class="text-[10px] uppercase tracking-[0.05em] text-ink55 bg-paperAlt rounded px-1.5 py-0.5">
                {e.source}
              </span>
              <span :if={e.note} class="text-ink55 truncate">{e.note}</span>
              <span class="ml-auto tabular-nums font-medium text-ink">
                ${format_usd(e.amount_usd)}
              </span>
              <button
                :if={e.source != :subscription}
                type="button"
                class="text-ink40 hover:text-red cursor-pointer"
                phx-click="delete_revenue"
                phx-value-id={e.id}
              >
                <Liid.icon name="x" size={12} />
              </button>
            </div>
            <div :if={@entries == []} class="text-ink40 text-[12px]">no revenue recorded yet</div>
          </div>
        </div>

        <.form
          for={@form}
          phx-submit="add_revenue"
          class="border-t border-border pt-5"
        >
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-2">
            add revenue (invoice / manual)
          </div>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-2 items-end">
            <label class="block">
              <span class="text-[10px] text-ink55">month</span>
              <input
                name="revenue[month]"
                value={@form[:month].value}
                placeholder="YYYY-MM"
                class="w-full mt-0.5 border border-border rounded-[8px] px-2 py-1.5 text-[13px] tabular-nums bg-card"
              />
            </label>
            <label class="block">
              <span class="text-[10px] text-ink55">amount $</span>
              <input
                name="revenue[amount_usd]"
                value={@form[:amount_usd].value}
                inputmode="decimal"
                class="w-full mt-0.5 border border-border rounded-[8px] px-2 py-1.5 text-[13px] tabular-nums bg-card"
              />
            </label>
            <label class="block">
              <span class="text-[10px] text-ink55">source</span>
              <select
                name="revenue[source]"
                class="w-full mt-0.5 border border-border rounded-[8px] px-2 py-1.5 text-[13px] bg-card"
              >
                <option value="invoice" selected={@form[:source].value == "invoice"}>invoice</option>
                <option value="manual" selected={@form[:source].value == "manual"}>manual</option>
              </select>
            </label>
            <button
              type="submit"
              class="bg-accent text-white rounded-[8px] px-3 py-1.5 text-[13px] font-medium cursor-pointer hover:opacity-90"
            >
              Record
            </button>
          </div>
          <input
            name="revenue[note]"
            value={@form[:note].value}
            placeholder="note (optional)"
            class="w-full mt-2 border border-border rounded-[8px] px-2 py-1.5 text-[13px] bg-card"
          />
        </.form>
      </div>
    </div>
    """
  end

  defp profit_cell(%{value: :empty} = assigns), do: ~H|<span class="text-ink40">—</span>|

  defp profit_cell(assigns) do
    ~H"""
    <span class={profit_color(@value)}>{format_signed(@value)}</span>
    """
  end

  defp stat(assigns) do
    assigns = assign_new(assigns, :class, fn -> "text-ink" end)

    ~H"""
    <div class="border border-border rounded-[8px] bg-paperAlt px-3 py-2.5">
      <div class="text-[10px] uppercase tracking-[0.06em] text-ink55">{@label}</div>
      <div class={["text-[17px] font-bold tabular-nums tracking-[-0.01em] mt-0.5", @class]}>
        {@value}
      </div>
    </div>
    """
  end

  # --- helpers --------------------------------------------------------------

  defp new_form do
    Phoenix.Component.to_form(
      %{"month" => current_ym(), "amount_usd" => "", "source" => "invoice", "note" => ""},
      as: :revenue
    )
  end

  defp sum_by_user_month(rows, amount_key) do
    Enum.reduce(rows, %{}, fn row, acc ->
      Map.update(acc, {row.user_id, row.month}, to_dec(Map.get(row, amount_key)), fn existing ->
        Decimal.add(existing, to_dec(Map.get(row, amount_key)))
      end)
    end)
  end

  # Per-month profit for one client: :empty when neither revenue nor cost exists,
  # otherwise revenue − cost for that month.
  defp month_profits(rev_um, cost_um, id, months) do
    Map.new(months, fn m ->
      rev = cell(rev_um, id, m)
      cost = cell(cost_um, id, m)

      value =
        if Decimal.equal?(rev, 0) and Decimal.equal?(cost, 0),
          do: :empty,
          else: Decimal.sub(rev, cost)

      {m, value}
    end)
  end

  defp sum_over_months(um, user_id, months) do
    Enum.reduce(months, Decimal.new(0), fn m, acc ->
      Decimal.add(acc, cell(um, user_id, m))
    end)
  end

  defp month_profit(_clients, month, cost_um, rev_um) do
    user_ids = (Map.keys(cost_um) ++ Map.keys(rev_um)) |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    Enum.reduce(user_ids, Decimal.new(0), fn id, acc ->
      Decimal.add(acc, month_cell_profit(rev_um, cost_um, id, month))
    end)
  end

  defp month_cell_profit(rev_um, cost_um, user_id, month) do
    Decimal.sub(cell(rev_um, user_id, month), cell(cost_um, user_id, month))
  end

  defp cell(um, user_id, month), do: Map.get(um, {user_id, month}, Decimal.new(0))

  defp margin(%{revenue: revenue, profit: profit}) do
    if Decimal.compare(revenue, 0) == :gt do
      pct = profit |> Decimal.div(revenue) |> Decimal.mult(100) |> Decimal.round(0)
      "#{Decimal.to_string(pct, :normal)}%"
    else
      "—"
    end
  end

  defp profit_color(d) do
    case d |> to_dec() |> Decimal.round(0) |> Decimal.compare(0) do
      :lt -> "text-red"
      :eq -> "text-ink70"
      :gt -> "text-green"
    end
  end

  defp current_ym do
    %{year: y, month: m} = DateTime.utc_now()
    "#{y}-#{m |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp blank_to_nil(s) when is_binary(s), do: if(String.trim(s) == "", do: nil, else: s)
  defp blank_to_nil(_), do: nil

  defp to_dec(%Decimal{} = d), do: d
  defp to_dec(n) when is_integer(n), do: Decimal.new(n)
  defp to_dec(n) when is_float(n), do: Decimal.from_float(n)
  defp to_dec(_), do: Decimal.new(0)

  # Whole dollars throughout — the user doesn't want cents.
  defp format_usd(%Decimal{} = d), do: d |> Decimal.round(0) |> Decimal.to_string(:normal)
  defp format_usd(n), do: n |> to_dec() |> format_usd()

  defp format_cost(d), do: format_usd(d)

  defp format_signed(d) do
    rounded = d |> to_dec() |> Decimal.round(0)

    cond do
      Decimal.equal?(rounded, 0) ->
        "$0"

      Decimal.compare(rounded, 0) == :lt ->
        "-$" <> (rounded |> Decimal.abs() |> Decimal.to_string(:normal))

      true ->
        "$" <> Decimal.to_string(rounded, :normal)
    end
  end
end
