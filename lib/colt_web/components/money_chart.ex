defmodule ColtWeb.Components.MoneyChart do
  @moduledoc """
  The revenue-vs-cost line chart shared by `/admin/costs` (all clients) and
  `/admin/clients/:id` (one client). Plain inline SVG — no JS, no library.

  Feed it a chronological list of `%{month: "YYYY-MM", revenue: _, cost: _}`
  (Decimals or numbers); `build/1` turns that into the geometry the component
  renders.
  """

  use Phoenix.Component

  @revenue "#3b7ae0"
  @cost "#d98a2b"

  @doc """
  Geometry for a chronological month series. Returns `%{points, cost_line,
  revenue_line, revenue_any}`.
  """
  def build(series) do
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

  attr :chart, :map, required: true
  attr :label, :string, default: "cost vs revenue · monthly"

  def money_chart(assigns) do
    assigns = assign(assigns, revenue_color: @revenue, cost_color: @cost)

    ~H"""
    <div
      class="bg-card border border-border rounded-[11px] p-5 md:p-6"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="flex items-center justify-between mb-4">
        <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55">
          {@label}
        </div>
        <div class="flex items-center gap-4 text-[11px] text-ink70">
          <span class="flex items-center gap-1.5">
            <span class="w-2.5 h-2.5 rounded-full" style={"background:#{@revenue_color}"}></span>
            revenue
          </span>
          <span class="flex items-center gap-1.5">
            <span class="w-2.5 h-2.5 rounded-full" style={"background:#{@cost_color}"}></span> cost
          </span>
        </div>
      </div>

      <svg :if={@chart.points != []} viewBox="0 0 720 220" class="w-full" style="height:220px">
        <polyline
          :if={@chart.revenue_any}
          fill="none"
          stroke={@revenue_color}
          stroke-width="2"
          points={@chart.revenue_line}
        />
        <polyline fill="none" stroke={@cost_color} stroke-width="2" points={@chart.cost_line} />

        <g :for={p <- @chart.points}>
          <circle :if={@chart.revenue_any} cx={p.x} cy={p.ry} r="3" fill={@revenue_color} />
          <circle cx={p.x} cy={p.cy} r="3" fill={@cost_color} />
          <text x={p.x} y="214" text-anchor="middle" font-size="10" fill="#9b978f">{p.label}</text>
        </g>
      </svg>

      <div :if={@chart.points == []} class="text-ink40 text-[13px]">not enough data yet</div>
    </div>
    """
  end

  defp month_label(<<_y::binary-size(4), "-", mm::binary-size(2)>>), do: mm
  defp month_label(m), do: m

  defp to_f(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_f(n) when is_number(n), do: n / 1
  defp to_f(_), do: 0.0
end
