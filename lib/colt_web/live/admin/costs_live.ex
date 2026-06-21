defmodule ColtWeb.Admin.CostsLive do
  use ColtWeb, :live_view

  import Ecto.Query

  alias Colt.Repo
  alias Colt.Resources.ApiCall
  alias Colt.Services.Costs.MonthlySummary
  alias ColtWeb.Admin.Summary
  alias ColtWeb.Components.{ApiCallLog, Liid}

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  def mount(_params, _session, socket) do
    {:ok, summary} = MonthlySummary.run(12)
    months = group_by_month(summary)
    current_month = current_ym()

    current =
      Enum.find(months, &(&1.month == current_month)) ||
        %{month: current_month, total: Decimal.new(0), calls: 0, providers: []}

    openrouter = ApiCall.recent_by_provider!(:openrouter, 50)
    google = ApiCall.recent_by_provider!(:google_cse, 50)
    by_task = task_breakdown(current_month)

    {:ok,
     socket
     |> assign(:months, months)
     |> assign(:current, current)
     |> assign(:openrouter, openrouter)
     |> assign(:google, google)
     |> assign(:by_task, by_task)
     |> assign(:open_call, nil)}
  end

  def handle_event("open_call", %{"id" => id}, socket) do
    case ApiCall.get_by_id(id, authorize?: false) do
      {:ok, call} -> {:noreply, assign(socket, open_call: call)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_call", _params, socket) do
    {:noreply, assign(socket, open_call: nil)}
  end

  # Current-month spend + call count grouped by task, sorted by cost desc.
  defp task_breakdown(month) do
    [yyyy, mm] = String.split(month, "-")
    {y, _} = Integer.parse(yyyy)
    {m, _} = Integer.parse(mm)
    {:ok, from_dt} = NaiveDateTime.new(y, m, 1, 0, 0, 0)
    to_dt = NaiveDateTime.add(from_dt, 31 * 24 * 3600, :second)

    from(c in "api_calls",
      where: c.inserted_at >= ^from_dt and c.inserted_at < ^to_dt,
      group_by: [c.task, c.provider],
      select: %{
        task: c.task,
        provider: c.provider,
        calls: count(c.id),
        cost_usd: sum(c.cost_usd)
      },
      order_by: [desc: sum(c.cost_usd)]
    )
    |> Repo.all()
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-10">
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />
        <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">API <em>costs</em></h1>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div
            class="bg-card border border-border rounded-[11px] md:col-span-2 p-6"
            style="box-shadow:var(--shadow-card)"
          >
            <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55">
              this month · {@current.month}
            </div>
            <div class="text-[56px] font-bold tabular-nums leading-none tracking-[-0.02em] text-ink mt-2">
              ${format_money(@current.total)}
            </div>
            <div class="text-[13px] text-ink55 mt-2">
              {@current.calls} calls
            </div>
            <div class="mt-4 space-y-1 text-[13px]">
              <div
                :for={p <- @current.providers}
                class="flex justify-between border-b border-border py-1 text-ink70"
              >
                <span>{p.provider} · {p.calls}</span>
                <span class="tabular-nums text-ink">${format_money(p.cost_usd)}</span>
              </div>
            </div>
          </div>

          <div
            class="bg-card border border-border rounded-[11px] p-6"
            style="box-shadow:var(--shadow-card)"
          >
            <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55">
              last 12 months
            </div>
            <div class="space-y-1 mt-2 text-[13px]">
              <div
                :for={m <- @months}
                class="flex justify-between border-b border-border py-1 text-ink70"
              >
                <span>{m.month}</span>
                <span class="tabular-nums text-ink">${format_money(m.total)}</span>
              </div>
            </div>
          </div>
        </div>

        <div>
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-2">
            this month · by task
          </div>
          <div
            class="border border-border rounded-[11px] bg-card overflow-x-auto"
            style="box-shadow:var(--shadow-card)"
          >
            <table class="text-[12px] w-full min-w-[480px]">
              <thead>
                <tr class="border-b border-border bg-paperAlt text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55">
                  <th class="text-left px-3 py-2">task</th>
                  <th class="text-left px-3 py-2">provider</th>
                  <th class="text-right px-3 py-2">calls</th>
                  <th class="text-right px-3 py-2">$</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={t <- @by_task}
                  class="border-b border-border last:border-b-0 hover:bg-paperAlt"
                >
                  <td class="px-3 py-1.5 text-ink">{t.task || "—"}</td>
                  <td class="px-3 py-1.5 text-ink70">{t.provider}</td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink70">{t.calls}</td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink">
                    ${format_money(t.cost_usd)}
                  </td>
                </tr>
                <tr :if={@by_task == []}>
                  <td colspan="4" class="px-3 py-2 text-ink40">no calls this month yet</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-2">
            openrouter · recent 50
          </div>
          <div
            class="border border-border rounded-[11px] bg-card overflow-x-auto"
            style="box-shadow:var(--shadow-card)"
          >
            <table class="text-[12px] w-full min-w-[480px]">
              <thead>
                <tr class="border-b border-border bg-paperAlt text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55">
                  <th class="text-left px-3 py-2">time</th>
                  <th class="text-left px-3 py-2">task</th>
                  <th class="text-left px-3 py-2">model</th>
                  <th class="text-right px-3 py-2">in</th>
                  <th class="text-right px-3 py-2">out</th>
                  <th class="text-right px-3 py-2">$</th>
                  <th class="text-right px-3 py-2">ms</th>
                  <th class="text-left px-3 py-2">status</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={c <- @openrouter}
                  class="border-b border-border last:border-b-0 cursor-pointer hover:bg-paperAlt"
                  phx-click="open_call"
                  phx-value-id={c.id}
                >
                  <td class="px-3 py-1.5 tabular-nums text-ink70">{format_time(c.inserted_at)}</td>
                  <td class="px-3 py-1.5 text-ink">{c.task || "—"}</td>
                  <td class="px-3 py-1.5 truncate max-w-[14rem] text-ink70">{c.model}</td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink70">{c.input_tokens}</td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink70">{c.output_tokens}</td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink">
                    {format_money(c.cost_usd)}
                  </td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink70">{c.latency_ms}</td>
                  <td class={[
                    "px-3 py-1.5 font-medium",
                    if(c.status == :error, do: "text-red", else: "text-green")
                  ]}>
                    {c.status}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-2">
            google cse · recent 50
          </div>
          <div
            class="border border-border rounded-[11px] bg-card overflow-x-auto"
            style="box-shadow:var(--shadow-card)"
          >
            <table class="text-[12px] w-full min-w-[480px]">
              <thead>
                <tr class="border-b border-border bg-paperAlt text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55">
                  <th class="text-left px-3 py-2">time</th>
                  <th class="text-left px-3 py-2">task</th>
                  <th class="text-left px-3 py-2">query</th>
                  <th class="text-right px-3 py-2">results</th>
                  <th class="text-right px-3 py-2">$</th>
                  <th class="text-right px-3 py-2">ms</th>
                  <th class="text-left px-3 py-2">status</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={c <- @google}
                  class="border-b border-border last:border-b-0 cursor-pointer hover:bg-paperAlt"
                  phx-click="open_call"
                  phx-value-id={c.id}
                >
                  <td class="px-3 py-1.5 tabular-nums text-ink70">{format_time(c.inserted_at)}</td>
                  <td class="px-3 py-1.5 text-ink">{c.task || "—"}</td>
                  <td class="px-3 py-1.5 truncate max-w-[24rem] text-ink70">{c.query}</td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink70">{c.results_count}</td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink">
                    {format_money(c.cost_usd)}
                  </td>
                  <td class="px-3 py-1.5 text-right tabular-nums text-ink70">{c.latency_ms}</td>
                  <td class={[
                    "px-3 py-1.5 font-medium",
                    if(c.status == :error, do: "text-red", else: "text-green")
                  ]}>
                    {c.status}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div
        :if={@open_call}
        class="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
        style="background: rgba(20,18,14,0.45); backdrop-filter: blur(2px);"
      >
        <div
          class="bg-card border border-border rounded-[11px] w-full max-w-[920px] my-auto px-6 py-7 md:px-9 md:pt-8 md:pb-7"
          style="box-shadow: 0 24px 80px rgba(0,0,0,0.18);"
          phx-click-away="close_call"
          phx-window-keydown="close_call"
          phx-key="escape"
        >
          <div class="flex justify-between items-start gap-3 mb-5">
            <div class="min-w-0">
              <div class="text-[10px] font-semibold tracking-[0.08em] uppercase text-ink55 mb-1.5 truncate">
                API call · {@open_call.task || "—"}
              </div>
              <h2 class="font-semibold text-[22px] md:text-[26px] leading-[1.15] tracking-[-0.02em] text-ink m-0">
                {@open_call.model || @open_call.provider}
              </h2>
            </div>
            <button
              type="button"
              class="w-6 h-6 flex items-center justify-center cursor-pointer"
              phx-click="close_call"
            >
              <Liid.icon name="x" size={14} />
            </button>
          </div>

          <ApiCallLog.api_call_detail call={@open_call} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp group_by_month(rows) do
    rows
    |> Enum.group_by(& &1.month)
    |> Enum.map(fn {month, entries} ->
      total = Enum.reduce(entries, Decimal.new(0), &Decimal.add(&2, &1.cost_usd))
      calls = Enum.reduce(entries, 0, &(&2 + &1.calls))

      %{
        month: month,
        total: total,
        calls: calls,
        providers: Enum.sort_by(entries, & &1.provider)
      }
    end)
    |> Enum.sort_by(& &1.month, :desc)
  end

  defp current_ym do
    %{year: y, month: m} = DateTime.utc_now()
    "#{y}-#{m |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp format_money(nil), do: "0.0000"
  defp format_money(%Decimal{} = d), do: d |> Decimal.round(4) |> Decimal.to_string(:normal)
  defp format_money(n) when is_number(n), do: n |> Decimal.from_float() |> format_money()
  defp format_money(_), do: "0.0000"

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M:%S")
  defp format_time(_), do: ""
end
