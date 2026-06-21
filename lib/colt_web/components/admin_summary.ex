defmodule ColtWeb.Admin.Summary do
  @moduledoc false
  use Phoenix.Component
  use Memoize

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
      %{
        kicker: "Clients",
        title: "Spending",
        value: format_int(current_month_clients()) <> " clients",
        path: "/admin/clients-spending"
      },
      %{
        kicker: "Clients",
        title: "All Users",
        value: format_int(Ash.count!(Colt.Accounts.User, authorize?: false)) <> " users",
        path: "/admin/clients"
      },
      oban_tile(),
      system_tile(),
      %{
        kicker: "Email",
        title: "Tracking",
        value: tracking_domain_summary(),
        path: "/admin/tracking-domain"
      }
    ]
  end

  defp tracking_domain_summary do
    case Colt.AppSettings.tracking_domain() do
      nil -> "unset"
      d -> d
    end
  end

  attr :tiles, :list, required: true
  attr :current_path, :string, default: nil

  def summary_strip(assigns) do
    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
      <%= for tile <- @tiles do %>
        <.strip_tile tile={tile} active={active?(tile, @current_path)} />
      <% end %>
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
      class={tile_class(@active)}
      style={"box-shadow:var(--shadow)" <> if(@active, do: ";box-shadow: inset 0 0 0 1px var(--accentRing), var(--shadow)", else: "")}
    >
      <.strip_body tile={@tile} active={@active} />
    </a>
    """
  end

  defp strip_tile(assigns) do
    ~H"""
    <.link
      navigate={@tile.path}
      class={tile_class(@active)}
      style={"box-shadow:var(--shadow)" <> if(@active, do: ";box-shadow: inset 0 0 0 1px var(--accentRing), var(--shadow)", else: "")}
    >
      <.strip_body tile={@tile} active={@active} />
    </.link>
    """
  end

  defp tile_class(active) do
    [
      "px-[16px] py-[14px] relative text-left cursor-pointer transition-colors border rounded-[11px]",
      if(active,
        do: "bg-accentSoft border-accentRing",
        else: "bg-card border-border hover:bg-paperAlt"
      )
    ]
  end

  attr :tile, :map, required: true
  attr :active, :boolean, default: false

  defp strip_body(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-1.5">
      <span class={[
        "text-[10.5px] font-semibold tracking-[0.08em] uppercase truncate",
        if(@active, do: "text-accent", else: "text-ink55")
      ]}>
        {@tile.title}
      </span>
      <span
        :if={Map.get(@tile, :alert)}
        class="w-1.5 h-1.5 rounded-full bg-red shrink-0"
        title="needs attention"
      >
      </span>
    </div>
    <div class={[
      "text-[27px] font-bold leading-none tracking-[-0.02em] tabular-nums truncate",
      cond do
        @active -> "text-accent"
        Map.get(@tile, :alert) -> "text-red"
        true -> "text-ink"
      end
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
      class="block bg-card hover:bg-paperAlt border border-border rounded-[11px] transition-colors"
      style="box-shadow:var(--shadow)"
    >
      <.tile_card_body tile={@tile} />
    </a>
    """
  end

  defp tile_card(assigns) do
    ~H"""
    <.link
      navigate={@tile.path}
      class="block bg-card hover:bg-paperAlt border border-border rounded-[11px] transition-colors"
      style="box-shadow:var(--shadow)"
    >
      <.tile_card_body tile={@tile} />
    </.link>
    """
  end

  attr :tile, :map, required: true

  defp tile_card_body(assigns) do
    ~H"""
    <div class="p-5">
      <div class="text-[10.5px] font-semibold uppercase tracking-[0.08em] text-ink55">
        {@tile.kicker}
      </div>
      <div class="text-[17px] font-bold text-ink mt-0.5">{@tile.title}</div>
      <div class={[
        "text-[13px] tabular-nums mt-1",
        if(Map.get(@tile, :alert), do: "text-red font-semibold", else: "text-ink70")
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

  # The grouped client_spending query is heavy and the count barely moves, so
  # cache it for 4h. expires_in is in milliseconds.
  defmemop current_month_clients, expires_in: 4 * 60 * 60 * 1000 do
    ym = current_ym()

    1
    |> Colt.Resources.ApiCall.client_spending!(authorize?: false)
    |> Enum.count(&(&1.month == ym))
  end

  defp current_ym do
    %{year: y, month: m} = DateTime.utc_now()
    "#{y}-#{m |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp format_money(%Decimal{} = d) do
    "$" <> (d |> Decimal.round(2) |> Decimal.to_string(:normal))
  end
end
