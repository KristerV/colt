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
        value: format_int(Ash.count!(Colt.Resources.Campaign, authorize?: false)) <> " total",
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
    <div class="flex flex-col sm:flex-row sm:flex-wrap lg:flex-nowrap overflow-x-auto lg:overflow-visible border border-rule rounded-sharp">
      <%= for {tile, i} <- Enum.with_index(@tiles) do %>
        <% active = active?(tile, @current_path) %>
        <.strip_tile
          tile={tile}
          active={active}
          first?={i == 0}
          last?={i == length(@tiles) - 1}
        />
      <% end %>
    </div>
    """
  end

  attr :tile, :map, required: true
  attr :active, :boolean, default: false
  attr :first?, :boolean, default: false
  attr :last?, :boolean, default: false

  defp strip_tile(%{tile: %{external: true}} = assigns) do
    ~H"""
    <a
      href={@tile.path}
      target="_blank"
      rel="noopener"
      class={tile_class(@active, @last?)}
      style={@active && "box-shadow: inset 0 -2px 0 var(--accent);"}
    >
      <.strip_body tile={@tile} active={@active} />
    </a>
    """
  end

  defp strip_tile(assigns) do
    ~H"""
    <.link
      navigate={@tile.path}
      class={tile_class(@active, @last?)}
      style={@active && "box-shadow: inset 0 -2px 0 var(--accent);"}
    >
      <.strip_body tile={@tile} active={@active} />
    </.link>
    """
  end

  defp tile_class(active, last?) do
    [
      "shrink-0 sm:shrink sm:flex-1 min-w-[140px] sm:min-w-0 px-[14px] py-[12px] lg:px-[16px] lg:py-[14px] relative text-left cursor-pointer bg-transparent hover:bg-paperAlt transition-colors",
      !last? && "border-b sm:border-b-0 sm:border-r border-rule",
      active && "bg-paperAlt"
    ]
  end

  attr :tile, :map, required: true
  attr :active, :boolean, default: false

  defp strip_body(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-1.5">
      <span class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 truncate">
        {@tile.title}
      </span>
      <span :if={Map.get(@tile, :alert)} class="font-mono text-[10px] text-error">!</span>
    </div>
    <div class={[
      "font-serif text-[28px] font-normal leading-none tracking-[-0.02em] tnum truncate",
      if(Map.get(@tile, :alert), do: "text-error", else: "text-ink")
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
