defmodule ColtWeb.Admin.ContactCostsLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign
  alias Colt.Services.Costs.ContactCostByMonth

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  @months_back 12
  @active_days 30
  @accent "#3b7ae0"

  def mount(_params, _session, socket) do
    {:ok, months} = ContactCostByMonth.run(@months_back)

    since = DateTime.add(DateTime.utc_now(), -@active_days * 86_400, :second)

    campaigns =
      Campaign.list_active_with_costs!(since,
        actor: socket.assigns.current_user,
        load: [:owner, :cost_usd, :done_count, :total_count]
      )

    {:ok,
     socket
     |> assign(:page_title, "Admin · Contact costs")
     |> assign(:active_days, @active_days)
     |> assign(:months, months)
     |> assign(:chart, build_chart(months))
     |> assign(:by_owner, group_by_owner(campaigns))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <div>
          <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">
            Contact <em>costs</em>
          </h1>
          <div class="text-[13px] text-ink55 mt-1">
            Gross spend (scans, searches, LLM calls) per enriched contact
          </div>
        </div>

        <.chart_card chart={@chart} />

        <div>
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-2">
            By campaign · active in the last {@active_days} days · grouped by owner
          </div>

          <div :if={@by_owner == []} class="text-ink40 text-[13px]">
            no campaign spend in this window
          </div>

          <div :for={{owner, rows} <- @by_owner} class="mb-5 last:mb-0">
            <div class="text-[13px] font-semibold text-ink mb-1.5">{owner}</div>

            <div
              class="border border-border rounded-[11px] bg-card overflow-hidden"
              style="box-shadow:var(--shadow-card)"
            >
              <div class="hidden md:grid items-center gap-3 px-4 py-2.5 border-b border-border bg-paperAlt text-[10px] font-semibold tracking-[0.08em] uppercase text-ink55 md:[grid-template-columns:2fr_100px_100px_120px_140px]">
                <span>Campaign</span>
                <span class="text-right">Enriched</span>
                <span class="text-right">Scanned</span>
                <span class="text-right">Total cost</span>
                <span class="text-right">$ / contact</span>
              </div>

              <.link
                :for={c <- rows}
                navigate={~p"/campaigns/#{c.id}/funnel"}
                class="grid grid-cols-2 md:[grid-template-columns:2fr_100px_100px_120px_140px] items-center gap-2 md:gap-3 px-4 py-3 border-b border-border last:border-b-0 hover:bg-paperAlt no-underline text-ink"
              >
                <span class="text-[13px] font-medium truncate">{c.name}</span>
                <span class="text-[12px] tabular-nums text-right">{c.done_count}</span>
                <span class="text-[12px] tabular-nums text-right">{c.total_count}</span>
                <span class="text-[12px] tabular-nums text-right">${fmt(c.cost_usd, 4)}</span>
                <span class="text-[12px] font-semibold tabular-nums text-right">
                  {per_contact(c)}
                </span>
              </.link>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- monthly chart ---------------------------------------------------------

  attr :chart, :map, required: true

  defp chart_card(assigns) do
    ~H"""
    <div
      class="bg-card border border-border rounded-[11px] p-5 md:p-6"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="flex items-center justify-between mb-4">
        <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55">
          avg $ per enriched contact · monthly
        </div>
      </div>

      <svg :if={@chart.bars != []} viewBox="0 0 720 220" class="w-full" style="height:220px">
        <g :for={b <- @chart.bars}>
          <rect
            x={b.x}
            y={b.y}
            width={b.w}
            height={b.h}
            rx="3"
            fill={b.color}
            opacity={if b.value, do: "1", else: "0.25"}
          >
            <title>{b.title}</title>
          </rect>
          <text
            :if={b.value}
            x={b.x + b.w / 2}
            y={b.y - 6}
            text-anchor="middle"
            font-size="10"
            fill="#37352f"
          >
            ${b.label}
          </text>
          <text
            x={b.x + b.w / 2}
            y="214"
            text-anchor="middle"
            font-size="10"
            fill="#9b978f"
          >
            {b.month_label}
          </text>
        </g>
      </svg>

      <div :if={@chart.bars == []} class="text-ink40 text-[13px]">not enough data yet</div>
    </div>
    """
  end

  # Bar geometry for a chronological month series of avg_cost_usd (nil = no
  # enriched contacts that month — rendered as a faint zero-height marker).
  defp build_chart(months) do
    values = months |> Enum.map(&to_f(&1.avg_cost_usd)) |> Enum.reject(&is_nil/1)
    max_val = values |> Enum.max(fn -> 0.0 end) |> max(0.0001)

    n = length(months)
    {x0, x1, y0, y1} = {20.0, 700.0, 20.0, 196.0}
    gap = 6.0
    slot = if n > 0, do: (x1 - x0) / n, else: x1 - x0
    bar_w = max(slot - gap, 4.0)

    bars =
      months
      |> Enum.with_index()
      |> Enum.map(fn {m, i} ->
        v = to_f(m.avg_cost_usd)
        h = if v, do: max(v / max_val * (y1 - y0), 2.0), else: 2.0
        x = x0 + slot * i + (slot - bar_w) / 2

        %{
          x: Float.round(x, 1),
          y: Float.round(y1 - h, 1),
          w: Float.round(bar_w, 1),
          h: Float.round(h, 1),
          value: v,
          label: if(v, do: fmt(m.avg_cost_usd, 2), else: nil),
          month_label: month_label(m.month),
          color: @accent,
          title: "#{m.month} · #{m.enriched} enriched · $#{fmt(m.cost_usd, 2)} total"
        }
      end)

    %{bars: bars}
  end

  defp month_label(<<_y::binary-size(4), "-", mm::binary-size(2)>>), do: mm
  defp month_label(m), do: m

  # --- per-campaign table -----------------------------------------------------

  defp group_by_owner(campaigns) do
    campaigns
    |> Enum.group_by(&owner_label(&1.owner))
    |> Enum.sort_by(fn {_owner, rows} -> -Enum.count(rows) end)
  end

  defp owner_label(%{email: e}), do: to_string(e)
  defp owner_label(_), do: "—"

  defp per_contact(%{done_count: 0}), do: "—"

  defp per_contact(%{done_count: n, cost_usd: cost}) when n > 0,
    do: "$" <> fmt(Decimal.div(to_dec(cost), Decimal.new(n)), 4)

  # --- formatting / coercion --------------------------------------------------

  defp to_f(nil), do: nil
  defp to_f(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_f(n) when is_number(n), do: n / 1

  defp to_dec(%Decimal{} = d), do: d
  defp to_dec(n) when is_number(n), do: Decimal.new(n)
  defp to_dec(_), do: Decimal.new(0)

  defp fmt(nil, _decimals), do: "0"

  defp fmt(%Decimal{} = d, decimals),
    do: d |> Decimal.round(decimals) |> Decimal.to_string(:normal)

  defp fmt(n, decimals) when is_number(n), do: n |> to_dec() |> fmt(decimals)
end
