defmodule ColtWeb.Admin.ClientsSpendingLive do
  use ColtWeb, :live_view

  alias Colt.Resources.ApiCall
  alias ColtWeb.Admin.Summary

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  @months_back 12

  def mount(_params, _session, socket) do
    rows = ApiCall.client_spending!(@months_back, authorize?: false)

    months =
      rows
      |> Enum.map(& &1.month)
      |> Enum.uniq()
      |> Enum.sort(:desc)
      |> Enum.take(@months_back)
      |> Enum.reverse()

    clients = build_clients(rows, months)
    current_month = current_ym()

    current_total =
      rows
      |> Enum.filter(&(&1.month == current_month))
      |> sum_cost()

    current_clients = rows |> Enum.filter(&(&1.month == current_month)) |> length()

    {:ok,
     socket
     |> assign(:months, months)
     |> assign(:clients, clients)
     |> assign(:current_month, current_month)
     |> assign(:current_total, current_total)
     |> assign(:current_clients, current_clients)}
  end

  # One row per client: %{email, by_month: %{month => cost}, total}, sorted by total desc.
  defp build_clients(rows, months) do
    rows
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {_user_id, user_rows} ->
      by_month = Map.new(user_rows, &{&1.month, to_decimal(&1.cost_usd)})

      %{
        email: user_rows |> hd() |> Map.get(:email) |> to_string(),
        by_month: Map.take(by_month, months),
        total:
          by_month
          |> Map.take(months)
          |> Map.values()
          |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
      }
    end)
    |> Enum.sort_by(& &1.total, &(Decimal.compare(&1, &2) != :lt))
  end

  defp sum_cost(rows) do
    Enum.reduce(rows, Decimal.new(0), &Decimal.add(&2, to_decimal(&1.cost_usd)))
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-10">
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />
        <h1 class="text-3xl font-semibold">Clients Spending</h1>

        <div class="card bg-base-200 border border-base-300 md:max-w-md">
          <div class="card-body">
            <div class="text-xs uppercase tracking-wider opacity-60 font-mono">
              this month · {@current_month}
            </div>
            <div class="font-serif text-7xl tabular-nums leading-none mt-2">
              ${format_money(@current_total)}
            </div>
            <div class="text-sm font-mono opacity-60 mt-2">
              {@current_clients} clients spending
            </div>
          </div>
        </div>

        <div>
          <div class="text-xs uppercase tracking-wider opacity-60 font-mono mb-2">
            per client · last {length(@months)} months · API cost incurred
          </div>
          <div class="overflow-x-auto">
            <table class="text-xs font-mono w-full min-w-[640px]">
              <thead class="opacity-60">
                <tr class="border-b border-base-300">
                  <th class="text-left py-1 pr-3">client</th>
                  <th :for={m <- @months} class="text-right py-1 pr-3 tabular-nums">{m}</th>
                  <th class="text-right py-1 pr-3">total</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={c <- @clients} class="border-b border-base-300/40">
                  <td class="py-1 pr-3 truncate max-w-[18rem]">{c.email}</td>
                  <td :for={m <- @months} class="py-1 pr-3 text-right tabular-nums">
                    {cell(c.by_month, m)}
                  </td>
                  <td class="py-1 pr-3 text-right tabular-nums font-semibold">
                    ${format_money(c.total)}
                  </td>
                </tr>
                <tr :if={@clients == []}>
                  <td colspan={length(@months) + 2} class="py-2 opacity-60">
                    no client spending in this period yet
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp cell(by_month, month) do
    case Map.get(by_month, month) do
      nil -> "—"
      cost -> "$" <> format_money(cost)
    end
  end

  defp current_ym do
    %{year: y, month: m} = DateTime.utc_now()
    "#{y}-#{m |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(_), do: Decimal.new(0)

  defp format_money(%Decimal{} = d), do: d |> Decimal.round(4) |> Decimal.to_string(:normal)
  defp format_money(n) when is_number(n), do: n |> to_decimal() |> format_money()
  defp format_money(_), do: "0.0000"
end
