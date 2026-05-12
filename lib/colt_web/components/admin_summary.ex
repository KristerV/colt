defmodule ColtWeb.Admin.Summary do
  @moduledoc false
  use Phoenix.Component

  require Ash.Query

  def tiles do
    open_feedback =
      Colt.Resources.Feedback
      |> Ash.Query.for_read(:count_open)
      |> Ash.count!()

    [
      %{
        kicker: "Support",
        title: "Feedback",
        value: format_int(open_feedback) <> " open",
        path: "/admin/feedback",
        alert: open_feedback > 0
      },
      %{
        kicker: "Data",
        title: "Companies",
        value: format_int(Ash.count!(Colt.Resources.Company)),
        path: "/admin/companies"
      },
      %{
        kicker: "Activity",
        title: "Campaigns",
        value: format_int(Ash.count!(Colt.Resources.Campaign)) <> " total",
        path: "/admin/campaigns"
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
      oban_tile(),
      system_tile()
    ]
  end

  attr :tiles, :list, required: true
  attr :current_path, :string, default: nil

  def summary_strip(assigns) do
    ~H"""
    <div class="border border-rule rounded-sharp overflow-hidden">
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-7 divide-x divide-y sm:divide-y-0 divide-rule">
        <.strip_tile :for={tile <- @tiles} tile={tile} active={active?(tile, @current_path)} />
      </div>
    </div>
    """
  end

  attr :tile, :map, required: true
  attr :active, :boolean, default: false

  defp strip_tile(%{tile: %{external: true}} = assigns) do
    ~H"""
    <a
      href={@tile.path}
      target="_blank"
      rel="noopener"
      class={["block px-3 py-2 hover:bg-paperAlt transition-colors", @active && "bg-paperAlt"]}
    >
      <.strip_body tile={@tile} active={@active} />
    </a>
    """
  end

  defp strip_tile(assigns) do
    ~H"""
    <.link
      navigate={@tile.path}
      class={["block px-3 py-2 hover:bg-paperAlt transition-colors", @active && "bg-paperAlt"]}
    >
      <.strip_body tile={@tile} active={@active} />
    </.link>
    """
  end

  attr :tile, :map, required: true
  attr :active, :boolean, default: false

  defp strip_body(assigns) do
    ~H"""
    <div class="font-mono text-[9px] tracking-[0.12em] uppercase text-ink55 flex items-center gap-1.5">
      <span class={["h-1 w-1 rounded-full", dot_class(@tile, @active)]}></span>
      {@tile.kicker}
    </div>
    <div class={["text-[13px] mt-0.5 truncate", @active && "font-semibold"]}>{@tile.title}</div>
    <div class={[
      "font-mono text-[11px] tabular-nums truncate",
      if(Map.get(@tile, :alert), do: "text-error font-semibold", else: "text-ink55")
    ]}>
      {@tile.value}
    </div>
    """
  end

  attr :tiles, :list, required: true

  def tile_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <.tile_card :for={tile <- @tiles} tile={tile} />
    </div>
    """
  end

  attr :tile, :map, required: true

  defp tile_card(%{tile: %{external: true}} = assigns) do
    ~H"""
    <a
      href={@tile.path}
      target="_blank"
      rel="noopener"
      class="card bg-base-200 hover:bg-base-300 border border-base-300 transition-colors"
    >
      <.tile_card_body tile={@tile} />
    </a>
    """
  end

  defp tile_card(assigns) do
    ~H"""
    <.link
      navigate={@tile.path}
      class="card bg-base-200 hover:bg-base-300 border border-base-300 transition-colors"
    >
      <.tile_card_body tile={@tile} />
    </.link>
    """
  end

  attr :tile, :map, required: true

  defp tile_card_body(assigns) do
    ~H"""
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
    """
  end

  defp active?(_tile, nil), do: false
  defp active?(%{external: true}, _path), do: false
  defp active?(%{path: path}, current), do: path == current

  defp dot_class(%{alert: true}, _), do: "bg-error"
  defp dot_class(_, true), do: "bg-ink"
  defp dot_class(_, _), do: "bg-ink20"

  defp system_tile do
    %{
      kicker: "System",
      title: "Resources",
      value: "CPU #{cpu_pct()}% · RAM #{ram_pct()}%",
      path: "/admin/system"
    }
  end

  defp cpu_pct do
    case :cpu_sup.util() do
      {:all, busy, _, _} -> round(busy)
      busy when is_number(busy) -> round(busy)
      _ -> 0
    end
  end

  defp ram_pct do
    data = :memsup.get_system_memory_data()
    total = Keyword.get(data, :total_memory) || Keyword.get(data, :system_total_memory)
    free = Keyword.get(data, :free_memory, 0)

    cached = Keyword.get(data, :cached_memory, 0)
    buffered = Keyword.get(data, :buffered_memory, 0)
    available = Keyword.get(data, :available_memory) || free + cached + buffered

    if is_integer(total) and total > 0 do
      round((total - available) * 100 / total)
    else
      0
    end
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
