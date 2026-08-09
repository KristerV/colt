defmodule ColtWeb.Admin.ClientsLive do
  use ColtWeb, :live_view

  alias Colt.Services.Admin.ClientList
  alias Colt.Services.Billing.RevenueSync
  alias ColtWeb.Components.{AdminFormat, Liid}

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  @default_sort {:registered, :desc}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin · Clients")
     |> assign(:sort, @default_sort)
     |> load()}
  end

  # --- events ---------------------------------------------------------------

  def handle_event("sort", %{"by" => by}, socket) do
    key = String.to_existing_atom(by)
    {:noreply, assign(socket, :sort, next_sort(socket.assigns.sort, key))}
  end

  def handle_event("refresh", _params, socket) do
    ClientList.refresh()
    {:noreply, socket |> put_flash(:info, "Recomputed") |> load()}
  end

  def handle_event("sync_stripe", _params, socket) do
    case RevenueSync.run() do
      {:ok, %{entries: n, clients: c}} ->
        ClientList.refresh()

        {:noreply,
         socket
         |> put_flash(:info, "Synced #{n} invoices across #{c} Stripe clients")
         |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Stripe sync failed: #{inspect(reason)}")}
    end
  end

  # --- data -----------------------------------------------------------------

  defp load(socket) do
    {:ok, %{rows: rows, totals: totals, computed_at: computed_at}} = ClientList.run()

    socket
    |> assign(:rows, rows)
    |> assign(:totals, totals)
    |> assign(:computed_at, computed_at)
  end

  # Clicking the active column flips it; a new column starts descending, except
  # the text one, where A→Z is the useful first press.
  defp next_sort({key, :desc}, key), do: {key, :asc}
  defp next_sort({key, :asc}, key), do: {key, :desc}
  defp next_sort(_current, :email), do: {:email, :asc}
  defp next_sort(_current, key), do: {key, :desc}

  defp sorted(rows, {key, dir}) do
    Enum.sort_by(rows, &sort_value(&1, key), sorter(dir))
  end

  # Microseconds, not seconds — two clients can register in the same second and
  # a truncated key would tie them into arbitrary order.
  defp sort_value(row, :registered),
    do: DateTime.to_unix(to_datetime(row.registered), :microsecond)

  defp sort_value(row, :email), do: row.email
  defp sort_value(row, key) when key in [:revenue, :cost, :profit], do: Decimal.to_float(row[key])
  defp sort_value(row, :plan), do: row.plan_eur
  defp sort_value(row, key), do: Map.fetch!(row, key)

  defp sorter(:asc), do: &<=/2
  defp sorter(:desc), do: &>=/2

  # --- render ---------------------------------------------------------------

  def render(assigns) do
    assigns = assign(assigns, :sorted, sorted(assigns.rows, assigns.sort))

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <div class="flex items-start justify-between gap-3 flex-wrap">
          <div>
            <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">
              All <em>clients</em>
            </h1>
            <div class="text-[13px] text-ink55 mt-1">
              computed {AdminFormat.ago(@computed_at)} · cached for 24h
            </div>
          </div>

          <div class="flex items-center gap-4">
            <button
              type="button"
              class="text-[12px] font-medium text-accent hover:underline cursor-pointer flex items-center gap-1.5"
              phx-click="sync_stripe"
            >
              <Liid.icon name="refresh" size={13} /> Sync Stripe revenue
            </button>
            <button
              type="button"
              class="text-[12px] font-medium text-accent hover:underline cursor-pointer flex items-center gap-1.5"
              phx-click="refresh"
            >
              <Liid.icon name="refresh" size={13} /> Refresh
            </button>
          </div>
        </div>

        <div class="grid grid-cols-2 md:grid-cols-5 gap-3">
          <AdminFormat.stat label="users" value={@totals.users} />
          <AdminFormat.stat label="paying" value={@totals.paying} />
          <AdminFormat.stat label="MRR" value={"€" <> Integer.to_string(@totals.mrr_eur)} />
          <AdminFormat.stat label="revenue · lifetime" value={AdminFormat.money(@totals.revenue)} />
          <AdminFormat.stat
            label="profit · lifetime"
            value={AdminFormat.signed(@totals.profit)}
            class={AdminFormat.profit_class(@totals.profit)}
          />
        </div>

        <div>
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-2">
            every client · campaigns → inboxes → with enriched → with sent → with interested
          </div>

          <div
            class="border border-border rounded-[11px] bg-card overflow-x-auto"
            style="box-shadow:var(--shadow-card)"
          >
            <table class="text-[12px] w-full min-w-[1000px]">
              <thead>
                <tr class="border-b border-border bg-paperAlt text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55">
                  <.th key={:email} sort={@sort} label="client" align="left" />
                  <.th key={:registered} sort={@sort} label="registered" align="left" />
                  <.th key={:plan} sort={@sort} label="plan" align="left" />
                  <.th key={:campaigns} sort={@sort} label="camp" />
                  <.th key={:inboxes} sort={@sort} label="inboxes" />
                  <.th key={:with_enriched} sort={@sort} label="enriched" />
                  <.th key={:with_sent} sort={@sort} label="sent" />
                  <.th key={:with_interested} sort={@sort} label="interested" />
                  <.th key={:revenue} sort={@sort} label="revenue" />
                  <.th key={:cost} sort={@sort} label="cost" />
                  <.th key={:profit} sort={@sort} label="profit" />
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={r <- @sorted}
                  class="border-b border-border last:border-b-0 hover:bg-paperAlt cursor-pointer"
                  phx-click={JS.navigate(~p"/admin/clients/#{r.id}")}
                >
                  <td class="px-3 py-2 truncate max-w-[18rem] text-ink font-medium">
                    {r.email}
                    <span :if={r.is_admin} class="text-ink40 font-normal">· admin</span>
                  </td>
                  <td class="px-3 py-2 tabular-nums text-ink70">
                    {AdminFormat.date(r.registered)}
                  </td>
                  <td class="px-3 py-2">
                    <span :if={r.plan} class={AdminFormat.status_class(r.status)}>{r.plan}</span>
                    <span :if={is_nil(r.plan)} class="text-ink40">—</span>
                  </td>
                  <.funnel_cell value={r.campaigns} />
                  <.funnel_cell value={r.inboxes} of={r.campaigns} />
                  <.funnel_cell value={r.with_enriched} of={r.campaigns} />
                  <.funnel_cell value={r.with_sent} of={r.with_enriched} />
                  <.funnel_cell value={r.with_interested} of={r.with_sent} />
                  <td class="px-3 py-2 text-right tabular-nums text-ink70">
                    {AdminFormat.money(r.revenue)}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-ink70">
                    {AdminFormat.money(r.cost)}
                  </td>
                  <td class={[
                    "px-3 py-2 text-right tabular-nums font-semibold",
                    AdminFormat.profit_class(r.profit)
                  ]}>
                    {AdminFormat.signed(r.profit)}
                  </td>
                </tr>
                <tr :if={@sorted == []}>
                  <td colspan="11" class="px-3 py-8 text-center text-ink40">no clients yet</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="text-[11px] text-ink40 mt-2">
            Cost is tracked API spend (OpenRouter + Google search) only — email verification,
            inbox seats and scraping aren't counted yet.
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :key, :atom, required: true
  attr :sort, :any, required: true
  attr :label, :string, required: true
  attr :align, :string, default: "right"

  defp th(assigns) do
    {active_key, dir} = assigns.sort
    assigns = assign(assigns, active?: active_key == assigns.key, dir: dir)

    ~H"""
    <th class={["px-3 py-2 font-semibold", "text-#{@align}"]}>
      <button
        type="button"
        class={["cursor-pointer hover:text-ink uppercase tracking-[0.06em]", @active? && "text-ink"]}
        phx-click="sort"
        phx-value-by={@key}
      >
        {@label}<span :if={@active?}>{if @dir == :desc, do: " ↓", else: " ↑"}</span>
      </button>
    </th>
    """
  end

  # A funnel step. Dimmed at zero, and amber when everything upstream fell away
  # here — that's the client who needs a call.
  attr :value, :integer, required: true
  attr :of, :integer, default: nil

  defp funnel_cell(assigns) do
    assigns = assign(assigns, stalled?: assigns.value == 0 and (assigns.of || 0) > 0)

    ~H"""
    <td class={[
      "px-3 py-2 text-right tabular-nums",
      cond do
        @stalled? -> "text-amber font-semibold"
        @value == 0 -> "text-ink40"
        true -> "text-ink70"
      end
    ]}>
      {@value}
    </td>
    """
  end

  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")
end
