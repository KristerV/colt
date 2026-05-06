defmodule ColtWeb.Admin.CostsLive do
  use ColtWeb, :live_view

  import Ecto.Query

  alias Colt.Repo
  alias Colt.Resources.ApiCall
  alias Colt.Services.Costs.MonthlySummary

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

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
     |> assign(:by_task, by_task)}
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
        <div>
          <.link navigate="/admin" class="text-sm opacity-60 hover:opacity-100">&larr; Admin</.link>
          <h1 class="text-3xl font-semibold mt-1">Costs</h1>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div class="card bg-base-200 border border-base-300 md:col-span-2">
            <div class="card-body">
              <div class="text-xs uppercase tracking-wider opacity-60 font-mono">
                this month · {@current.month}
              </div>
              <div class="font-serif text-7xl tabular-nums leading-none mt-2">
                ${format_money(@current.total)}
              </div>
              <div class="text-sm font-mono opacity-60 mt-2">
                {@current.calls} calls
              </div>
              <div class="mt-4 space-y-1 text-sm font-mono">
                <div
                  :for={p <- @current.providers}
                  class="flex justify-between border-b border-base-300 py-1"
                >
                  <span>{p.provider} · {p.calls}</span>
                  <span class="tabular-nums">${format_money(p.cost_usd)}</span>
                </div>
              </div>
            </div>
          </div>

          <div class="card bg-base-200 border border-base-300">
            <div class="card-body">
              <div class="text-xs uppercase tracking-wider opacity-60 font-mono">last 12 months</div>
              <div class="space-y-1 mt-2 text-sm font-mono">
                <div :for={m <- @months} class="flex justify-between border-b border-base-300 py-1">
                  <span>{m.month}</span>
                  <span class="tabular-nums">${format_money(m.total)}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div>
          <div class="text-xs uppercase tracking-wider opacity-60 font-mono mb-2">
            this month · by task
          </div>
          <div class="overflow-x-auto">
            <table class="text-xs font-mono w-full min-w-[480px]">
              <thead class="opacity-60">
                <tr class="border-b border-base-300">
                  <th class="text-left py-1 pr-3">task</th>
                  <th class="text-left py-1 pr-3">provider</th>
                  <th class="text-right py-1 pr-3">calls</th>
                  <th class="text-right py-1 pr-3">$</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={t <- @by_task} class="border-b border-base-300/40">
                  <td class="py-1 pr-3">{t.task || "—"}</td>
                  <td class="py-1 pr-3 opacity-70">{t.provider}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">{t.calls}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">${format_money(t.cost_usd)}</td>
                </tr>
                <tr :if={@by_task == []}>
                  <td colspan="4" class="py-2 opacity-60">no calls this month yet</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <div class="text-xs uppercase tracking-wider opacity-60 font-mono mb-2">
            openrouter · recent 50
          </div>
          <div class="overflow-x-auto">
            <table class="text-xs font-mono w-full min-w-[480px]">
              <thead class="opacity-60">
                <tr class="border-b border-base-300">
                  <th class="text-left py-1 pr-3">time</th>
                  <th class="text-left py-1 pr-3">task</th>
                  <th class="text-left py-1 pr-3">model</th>
                  <th class="text-right py-1 pr-3">in</th>
                  <th class="text-right py-1 pr-3">out</th>
                  <th class="text-right py-1 pr-3">$</th>
                  <th class="text-right py-1 pr-3">ms</th>
                  <th class="text-left py-1 pr-3">status</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={c <- @openrouter} class="border-b border-base-300/40">
                  <td class="py-1 pr-3 opacity-70">{format_time(c.inserted_at)}</td>
                  <td class="py-1 pr-3">{c.task || "—"}</td>
                  <td class="py-1 pr-3 truncate max-w-[14rem]">{c.model}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">{c.input_tokens}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">{c.output_tokens}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">{format_money(c.cost_usd)}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">{c.latency_ms}</td>
                  <td class={["py-1 pr-3", c.status == :error && "text-error"]}>{c.status}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <div class="text-xs uppercase tracking-wider opacity-60 font-mono mb-2">
            google cse · recent 50
          </div>
          <div class="overflow-x-auto">
            <table class="text-xs font-mono w-full min-w-[480px]">
              <thead class="opacity-60">
                <tr class="border-b border-base-300">
                  <th class="text-left py-1 pr-3">time</th>
                  <th class="text-left py-1 pr-3">task</th>
                  <th class="text-left py-1 pr-3">query</th>
                  <th class="text-right py-1 pr-3">results</th>
                  <th class="text-right py-1 pr-3">$</th>
                  <th class="text-right py-1 pr-3">ms</th>
                  <th class="text-left py-1 pr-3">status</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={c <- @google} class="border-b border-base-300/40">
                  <td class="py-1 pr-3 opacity-70">{format_time(c.inserted_at)}</td>
                  <td class="py-1 pr-3">{c.task || "—"}</td>
                  <td class="py-1 pr-3 truncate max-w-[24rem]">{c.query}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">{c.results_count}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">{format_money(c.cost_usd)}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">{c.latency_ms}</td>
                  <td class={["py-1 pr-3", c.status == :error && "text-error"]}>{c.status}</td>
                </tr>
              </tbody>
            </table>
          </div>
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
