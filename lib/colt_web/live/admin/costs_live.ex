defmodule ColtWeb.Admin.CostsLive do
  use ColtWeb, :live_view

  alias Colt.Resources.{ApiCall, RevenueEntry}
  alias Colt.Services.Costs.MonthlySummary
  alias ColtWeb.Admin.Summary
  alias ColtWeb.Components.{ApiCallLog, Liid}

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  @months_back 12

  def mount(_params, _session, socket) do
    {:ok, summary} = MonthlySummary.run(@months_back)
    {:ok, revenue} = RevenueEntry.monthly_totals(@months_back, authorize?: false)

    months = month_rows(summary)

    {:ok,
     socket
     |> assign(:months, months)
     |> assign(:chart, build_chart(months, revenue))
     |> assign(:expanded, MapSet.new())
     |> assign(:details, %{})
     |> assign(:open_call, nil)}
  end

  def handle_event("toggle_month", %{"month" => month}, socket) do
    if MapSet.member?(socket.assigns.expanded, month) do
      {:noreply, assign(socket, :expanded, MapSet.delete(socket.assigns.expanded, month))}
    else
      {:noreply, expand_month(socket, month)}
    end
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

  # Mark a month expanded and lazily load its detail (once).
  defp expand_month(socket, month) do
    expanded = MapSet.put(socket.assigns.expanded, month)

    details =
      if Map.has_key?(socket.assigns.details, month) do
        socket.assigns.details
      else
        Map.put(socket.assigns.details, month, load_detail(month))
      end

    socket |> assign(:expanded, expanded) |> assign(:details, details)
  end

  # Everything shown when a month is open: per end-provider, per task, per model,
  # and the recent calls — all scoped to that month, loaded on demand.
  defp load_detail(month) do
    {:ok, rows} = ApiCall.month_rollup(month, authorize?: false)
    recent = ApiCall.recent_in_month!(month, 50, authorize?: false)

    %{
      by_task: rollup(rows, &(&1.task || "—")),
      by_model: model_rollup(rows),
      recent: recent
    }
  end

  # Group fine-grained rows by `key_fun`, summing calls + cost. Sorted by cost desc.
  defp rollup(rows, key_fun) do
    rows
    |> Enum.group_by(key_fun)
    |> Enum.map(fn {key, group} ->
      %{key: key, calls: sum_int(group, :calls), cost: sum_dec(group, :cost_usd)}
    end)
    |> Enum.sort_by(& &1.cost, &(Decimal.compare(&1, &2) != :lt))
  end

  defp model_rollup(rows) do
    rows
    |> Enum.group_by(&model_key/1)
    |> Enum.map(fn {model, group} ->
      %{
        key: model,
        calls: sum_int(group, :calls),
        errors: sum_int(group, :errors),
        cost: sum_dec(group, :cost_usd),
        out: sum_int(group, :out_tokens)
      }
    end)
    |> Enum.sort_by(& &1.cost, &(Decimal.compare(&1, &2) != :lt))
  end

  # Search calls (Google CSE) carry no model id — surface them as their own
  # "search" row in the by-model table so they sit beside the LLM models.
  defp model_key(%{provider: :google_cse}), do: "search"
  defp model_key(%{model: model}), do: model || "—"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />
        <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">API <em>costs</em></h1>

        <.chart chart={@chart} />

        <div class="space-y-2">
          <div
            :for={m <- @months}
            class="bg-card border border-border rounded-[11px] overflow-hidden"
            style="box-shadow:var(--shadow-card)"
          >
            <button
              type="button"
              class="w-full flex items-center gap-3 px-5 py-4 text-left cursor-pointer hover:bg-paperAlt"
              phx-click="toggle_month"
              phx-value-month={m.month}
            >
              <Liid.icon
                name="chev-r"
                size={14}
                class={
                  "text-ink40 transition-transform " <>
                    if(MapSet.member?(@expanded, m.month), do: "rotate-90", else: "")
                }
              />
              <span class="text-[15px] font-semibold tabular-nums text-ink">{m.month}</span>
              <span class="text-[12px] text-ink55 tabular-nums">{m.calls} calls</span>
              <span class="ml-auto text-[19px] font-bold tabular-nums tracking-[-0.01em] text-ink">
                ${format_money(m.total)}
              </span>
            </button>

            <div :if={MapSet.member?(@expanded, m.month)} class="px-5 pb-5 pt-1 space-y-5">
              {render_detail(assigns, m.month)}
            </div>
          </div>

          <div :if={@months == []} class="text-ink40 text-[13px]">no API calls recorded yet</div>
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

  # --- month detail ---------------------------------------------------------

  defp render_detail(assigns, month) do
    assigns = assign(assigns, :detail, Map.get(assigns.details, month))

    ~H"""
    <div :if={@detail} class="space-y-5">
      <div>
        <.section_label>by model</.section_label>
        <div class="border border-border rounded-[8px] bg-card overflow-x-auto">
          <table class="text-[12px] w-full min-w-[460px]">
            <thead>
              <tr class="border-b border-border bg-paperAlt text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55">
                <th class="text-left px-3 py-2">model</th>
                <th class="text-right px-3 py-2">calls</th>
                <th class="text-right px-3 py-2">out tok</th>
                <th class="text-right px-3 py-2">$</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={r <- @detail.by_model}
                class="border-b border-border last:border-b-0 hover:bg-paperAlt"
              >
                <td class="px-3 py-1.5 text-ink">{r.key}</td>
                <td class="px-3 py-1.5 text-right tabular-nums text-ink70">
                  {r.calls}<span :if={r.errors > 0} class="text-red"> ({r.errors}✕)</span>
                </td>
                <td class="px-3 py-1.5 text-right tabular-nums text-ink70">{format_int(r.out)}</td>
                <td class="px-3 py-1.5 text-right tabular-nums text-ink">${format_money(r.cost)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <.mini_table title="by task" rows={@detail.by_task} />

      <div>
        <.section_label>recent calls</.section_label>
        <div class="border border-border rounded-[8px] bg-card overflow-x-auto">
          <table class="text-[12px] w-full min-w-[560px]">
            <thead>
              <tr class="border-b border-border bg-paperAlt text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55">
                <th class="text-left px-3 py-2">time</th>
                <th class="text-left px-3 py-2">task</th>
                <th class="text-left px-3 py-2">model / query</th>
                <th class="text-right px-3 py-2">$</th>
                <th class="text-right px-3 py-2">ms</th>
                <th class="text-left px-3 py-2">status</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={c <- @detail.recent}
                class="border-b border-border last:border-b-0 cursor-pointer hover:bg-paperAlt"
                phx-click="open_call"
                phx-value-id={c.id}
              >
                <td class="px-3 py-1.5 tabular-nums text-ink70">{format_time(c.inserted_at)}</td>
                <td class="px-3 py-1.5 text-ink">{c.task || "—"}</td>
                <td class="px-3 py-1.5 truncate max-w-[20rem] text-ink70">{c.model || c.query}</td>
                <td class="px-3 py-1.5 text-right tabular-nums text-ink">
                  ${format_micro(c.cost_usd)}
                </td>
                <td class="px-3 py-1.5 text-right tabular-nums text-ink70">{c.latency_ms}</td>
                <td class={[
                  "px-3 py-1.5 font-medium",
                  if(c.status == :error, do: "text-red", else: "text-green")
                ]}>
                  {c.status}
                </td>
              </tr>
              <tr :if={@detail.recent == []}>
                <td colspan="6" class="px-3 py-2 text-ink40">no calls this month</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp mini_table(assigns) do
    ~H"""
    <div>
      <.section_label>{@title}</.section_label>
      <div class="border border-border rounded-[8px] bg-card overflow-hidden">
        <div
          :for={r <- @rows}
          class="flex justify-between items-center px-3 py-1.5 border-b border-border last:border-b-0 text-[12px]"
        >
          <span class="text-ink70 truncate pr-3">{r.key} · {r.calls}</span>
          <span class="tabular-nums text-ink shrink-0">${format_money(r.cost)}</span>
        </div>
        <div :if={@rows == []} class="px-3 py-2 text-ink40 text-[12px]">none</div>
      </div>
    </div>
    """
  end

  defp section_label(assigns) do
    ~H"""
    <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-1.5">
      {render_slot(@inner_block)}
    </div>
    """
  end

  # --- chart ----------------------------------------------------------------

  defp chart(assigns) do
    ~H"""
    <div
      class="bg-card border border-border rounded-[11px] p-5 md:p-6"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="flex items-center justify-between mb-4">
        <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55">
          cost vs revenue · monthly
        </div>
        <div class="flex items-center gap-4 text-[11px] text-ink70">
          <span class="flex items-center gap-1.5">
            <span class="w-2.5 h-2.5 rounded-full" style="background:#3b7ae0"></span> revenue
          </span>
          <span class="flex items-center gap-1.5">
            <span class="w-2.5 h-2.5 rounded-full" style="background:#d98a2b"></span> cost
          </span>
        </div>
      </div>

      <svg :if={@chart.points != []} viewBox="0 0 720 220" class="w-full" style="height:220px">
        <polyline
          :if={@chart.revenue_any}
          fill="none"
          stroke="#3b7ae0"
          stroke-width="2"
          points={@chart.revenue_line}
        />
        <polyline fill="none" stroke="#d98a2b" stroke-width="2" points={@chart.cost_line} />

        <g :for={p <- @chart.points}>
          <circle :if={@chart.revenue_any} cx={p.x} cy={p.ry} r="3" fill="#3b7ae0" />
          <circle cx={p.x} cy={p.cy} r="3" fill="#d98a2b" />
          <text x={p.x} y="214" text-anchor="middle" font-size="10" fill="#9b978f">{p.label}</text>
        </g>
      </svg>

      <div :if={@chart.points == []} class="text-ink40 text-[13px]">not enough data yet</div>
    </div>
    """
  end

  # --- data shaping ---------------------------------------------------------

  # One row per month from the per-provider summary: total cost + call count.
  defp month_rows(summary) do
    summary
    |> Enum.group_by(& &1.month)
    |> Enum.map(fn {month, entries} ->
      %{
        month: month,
        total: Enum.reduce(entries, Decimal.new(0), &Decimal.add(&2, to_dec(&1.cost_usd))),
        calls: Enum.reduce(entries, 0, &(&2 + &1.calls))
      }
    end)
    |> ensure_current_month()
    |> Enum.sort_by(& &1.month, :desc)
  end

  defp ensure_current_month(months) do
    cm = current_ym()

    if Enum.any?(months, &(&1.month == cm)),
      do: months,
      else: [%{month: cm, total: Decimal.new(0), calls: 0} | months]
  end

  # Build SVG geometry for the cost + revenue lines over the (chronological) months.
  defp build_chart(months, revenue_rows) do
    rev_by_month = Map.new(revenue_rows, &{&1.month, to_dec(&1.amount_usd)})
    cost_by_month = Map.new(months, &{&1.month, &1.total})

    chron =
      (Map.keys(cost_by_month) ++ Map.keys(rev_by_month))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.take(-@months_back)

    series =
      Enum.map(chron, fn m ->
        %{
          month: m,
          cost: Map.get(cost_by_month, m, Decimal.new(0)),
          revenue: Map.get(rev_by_month, m, Decimal.new(0))
        }
      end)

    max_val =
      series
      |> Enum.flat_map(&[to_f(&1.cost), to_f(&1.revenue)])
      |> Enum.max(fn -> 0.0 end)
      |> max(0.0001)

    n = length(series)
    {x0, x1, y0, y1} = {20.0, 700.0, 16.0, 196.0}

    points =
      series
      |> Enum.with_index()
      |> Enum.map(fn {s, i} ->
        x = if n <= 1, do: (x0 + x1) / 2, else: x0 + (x1 - x0) * i / (n - 1)

        %{
          x: Float.round(x, 1),
          cy: Float.round(y1 - to_f(s.cost) / max_val * (y1 - y0), 1),
          ry: Float.round(y1 - to_f(s.revenue) / max_val * (y1 - y0), 1),
          label: month_label(s.month)
        }
      end)

    %{
      points: points,
      cost_line: Enum.map_join(points, " ", &"#{&1.x},#{&1.cy}"),
      revenue_line: Enum.map_join(points, " ", &"#{&1.x},#{&1.ry}"),
      revenue_any: Enum.any?(series, &(to_f(&1.revenue) > 0))
    }
  end

  defp month_label(<<_y::binary-size(4), "-", mm::binary-size(2)>>), do: mm
  defp month_label(m), do: m

  defp current_ym do
    %{year: y, month: m} = DateTime.utc_now()
    "#{y}-#{m |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  # --- formatting / coercion ------------------------------------------------

  defp sum_int(rows, key), do: Enum.reduce(rows, 0, &(&2 + to_int(Map.get(&1, key))))

  defp to_int(nil), do: 0
  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_float(n), do: round(n)
  defp to_int(%Decimal{} = d), do: d |> Decimal.round(0) |> Decimal.to_integer()

  defp sum_dec(rows, key),
    do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(&2, to_dec(Map.get(&1, key))))

  defp to_dec(%Decimal{} = d), do: d
  defp to_dec(n) when is_integer(n), do: Decimal.new(n)
  defp to_dec(n) when is_float(n), do: Decimal.from_float(n)
  defp to_dec(_), do: Decimal.new(0)

  defp to_f(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_f(n) when is_number(n), do: n / 1
  defp to_f(_), do: 0.0

  # Whole-dollar rounding for sums — the user doesn't want cents on totals.
  defp format_money(nil), do: "0"
  defp format_money(%Decimal{} = d), do: d |> Decimal.round(0) |> Decimal.to_string(:normal)
  defp format_money(n) when is_number(n), do: n |> to_dec() |> format_money()
  defp format_money(_), do: "0"

  # Sub-dollar precision, kept only for individual recent-call costs.
  defp format_micro(%Decimal{} = d), do: d |> Decimal.round(4) |> Decimal.to_string(:normal)
  defp format_micro(n) when is_number(n), do: n |> to_dec() |> format_micro()
  defp format_micro(_), do: "0.0000"

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M:%S")
  defp format_time(_), do: ""

  defp format_int(nil), do: "—"
  defp format_int(%Decimal{} = d), do: d |> Decimal.round(0) |> Decimal.to_string(:normal)
  defp format_int(n) when is_number(n), do: n |> round() |> Integer.to_string()
  defp format_int(_), do: "—"
end
