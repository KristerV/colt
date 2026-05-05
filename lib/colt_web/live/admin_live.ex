defmodule ColtWeb.AdminLive do
  use ColtWeb, :live_view

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :tiles, tiles())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <h1 class="text-3xl font-semibold">Admin</h1>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <.tile :for={tile <- @tiles} tile={tile} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :tile, :map, required: true

  defp tile(%{tile: %{external: true}} = assigns) do
    ~H"""
    <a
      href={@tile.path}
      target="_blank"
      rel="noopener"
      class="card bg-base-200 hover:bg-base-300 border border-base-300 transition-colors"
    >
      <div class="card-body">
        <div class="text-xs uppercase tracking-wider opacity-60">{@tile.kicker}</div>
        <div class="text-xl font-semibold">{@tile.title}</div>
        <div class={[
          "text-sm font-mono tabular-nums",
          if(Map.get(@tile, :alert), do: "text-error font-semibold", else: "opacity-70")
        ]}>
          {@tile.value}
        </div>
      </div>
    </a>
    """
  end

  defp tile(assigns) do
    ~H"""
    <.link
      navigate={@tile.path}
      class="card bg-base-200 hover:bg-base-300 border border-base-300 transition-colors"
    >
      <div class="card-body">
        <div class="text-xs uppercase tracking-wider opacity-60">{@tile.kicker}</div>
        <div class="text-xl font-semibold">{@tile.title}</div>
        <div class="text-sm font-mono tabular-nums opacity-70">{@tile.value}</div>
      </div>
    </.link>
    """
  end

  defp tiles do
    [
      %{
        kicker: "Data",
        title: "Companies",
        value: format_int(Ash.count!(Colt.Resources.Company)),
        path: "/admin/companies"
      },
      %{
        kicker: "Database",
        title: "Storage",
        value: ColtWeb.Admin.StorageLive.total_size(),
        path: "/admin/storage"
      },
      %{
        kicker: "Spend",
        title: "Costs",
        value: format_money(current_month_cost()),
        path: "/admin/costs"
      },
      oban_tile()
    ]
  end

  defp oban_tile do
    discarded = discarded_count()

    %{
      kicker: "Background",
      title: "Oban Jobs",
      value: format_int(discarded) <> " discarded",
      path: "/admin/oban",
      external: true,
      alert: discarded > 0
    }
  end

  defp discarded_count do
    import Ecto.Query

    from(j in Oban.Job, where: j.state == "discarded")
    |> Colt.Repo.aggregate(:count)
  end

  defp format_int(n),
    do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, " ")

  defp current_month_cost do
    {:ok, rows} = Colt.Services.Costs.MonthlySummary.run(1)
    ym = current_ym()

    rows
    |> Enum.filter(&(&1.month == ym))
    |> Enum.reduce(Decimal.new(0), &Decimal.add(&2, &1.cost_usd))
  end

  defp current_ym do
    %{year: y, month: m} = DateTime.utc_now()
    "#{y}-#{m |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp format_money(%Decimal{} = d) do
    "$" <> (d |> Decimal.round(2) |> Decimal.to_string(:normal))
  end
end
