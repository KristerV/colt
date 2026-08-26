defmodule ColtWeb.Admin.Summary do
  @moduledoc false
  use Phoenix.Component
  use Memoize

  require Ash.Query

  # Fixed category order for the admin index — each tile below carries a
  # `group:` naming one of these.
  @groups ["Users", "Money", "Demo", "System"]

  @cache_ms 24 * 60 * 60 * 1000

  def tiles do
    open_feedback =
      Colt.Resources.Feedback
      |> Ash.Query.for_read(:count_open)
      |> Ash.count!()

    new_leads = Colt.Resources.DemoLead.count_new!(authorize?: false)

    [
      client_tile(),
      %{
        group: "Users",
        title: "Feedback",
        value: format_int(open_feedback) <> " open",
        path: "/admin/feedback",
        alert: open_feedback > 0
      },
      %{
        group: "Users",
        title: "Campaigns",
        value: format_int(Ash.count!(Colt.Resources.Campaign, authorize?: false)) <> " total",
        path: "/admin/campaigns"
      },
      %{
        group: "Money",
        title: "Costs",
        value: format_money(current_month_cost()),
        path: "/admin/costs"
      },
      %{
        group: "Money",
        title: "Contact costs",
        value: contact_cost_summary(),
        path: "/admin/contact-costs"
      },
      %{
        group: "Demo",
        title: "Deck",
        value: deck_summary(),
        path: "/admin/deck"
      },
      %{
        group: "Demo",
        title: "A/B funnel",
        value: format_int(deck_views()) <> " views",
        path: "/admin/ab"
      },
      %{
        group: "Demo",
        title: "Demo leads",
        value: format_int(new_leads) <> " new",
        path: "/admin/demo-leads",
        alert: new_leads > 0
      },
      system_tile(),
      %{
        group: "System",
        title: "Storage",
        value: ColtWeb.Admin.StorageLive.total_size(),
        path: "/admin/storage"
      },
      %{
        group: "System",
        title: "Companies",
        value: format_approx(Colt.Resources.Company.estimated_count()),
        path: "/admin/countries"
      },
      %{
        group: "System",
        title: "Industry growth",
        value: industry_growth_summary(),
        path: "/admin/industries"
      },
      %{
        group: "System",
        title: "Tracking domain",
        value: tracking_domain_summary(),
        path: "/admin/tracking-domain"
      },
      oban_tile()
    ]
  end

  @doc "Tiles bucketed by `group:`, in the fixed category order."
  def grouped(tiles) do
    by_group = Enum.group_by(tiles, & &1.group)

    @groups
    |> Enum.map(&{&1, Map.get(by_group, &1, [])})
    |> Enum.reject(fn {_group, tiles} -> tiles == [] end)
  end

  # The tile shows the pair of years the page compares, not a computed figure:
  # the rollup is a full scan of two years of filings, too heavy for a tile that
  # renders on every admin page.
  # Total revenue growth across every market's "all industries combined"
  # figure — the same number the page's own headline tile shows, just summed
  # over markets instead of picked for one. The underlying rollup is a full
  # GROUPING SETS scan of two years of filings per market, too heavy to redo
  # on every admin index load — memoized for 24h, same as ClientList.
  defp industry_growth_summary, do: cached_industry_growth(admin_summary_code_version())

  defp admin_summary_code_version, do: __MODULE__.module_info(:md5)

  defmemop cached_industry_growth(_code_version), expires_in: @cache_ms do
    totals =
      Colt.Markets.atoms()
      |> Enum.map(&Colt.Services.Admin.IndustryGrowth.load/1)
      |> Enum.map(& &1.market_total)
      |> Enum.reject(&is_nil/1)

    case totals do
      [] ->
        "no data"

      rows ->
        base = Enum.reduce(rows, Decimal.new(0), &Decimal.add(&2, &1.base_total))
        latest = Enum.reduce(rows, Decimal.new(0), &Decimal.add(&2, &1.latest_total))
        growth_pct(latest, base)
    end
  end

  defp growth_pct(latest, base) do
    if Decimal.compare(base, 0) != :gt do
      "—"
    else
      change = latest |> Decimal.div(base) |> Decimal.sub(1) |> Decimal.mult(100)
      decimals = if Decimal.compare(Decimal.abs(change), 10) != :lt, do: 0, else: 1
      sign = if Decimal.positive?(change), do: "+", else: ""

      sign <> Decimal.to_string(Decimal.round(change, decimals), :normal) <> "%"
    end
  end

  defp deck_summary do
    variants = ColtWeb.Deck.Slides.variants() |> length()

    format_int(variants) <> " variants"
  end

  # Prospects who pressed play. ab_funnel ships an Ecto schema rather than an Ash
  # resource, so there is no action to add and call here.
  defp deck_views do
    require Ecto.Query

    AbFunnel.Resources.Event
    |> Ecto.Query.where(event: "deck_started")
    |> Colt.Repo.aggregate(:count)
  end

  defp tracking_domain_summary do
    case Colt.AppSettings.tracking_domain() do
      nil -> "unset"
      d -> d
    end
  end

  attr :tiles, :list, required: true
  attr :current_path, :string, default: nil

  @doc "Row-by-row admin index: one bounded card per category, one row per page."
  def summary_groups(assigns) do
    assigns = assign(assigns, :groups, grouped(assigns.tiles))

    ~H"""
    <div class="space-y-6">
      <div :for={{group, tiles} <- @groups}>
        <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-2">
          {group}
        </div>
        <div
          class="border border-border rounded-[11px] bg-card overflow-hidden"
          style="box-shadow:var(--shadow-card)"
        >
          <.summary_row
            :for={tile <- tiles}
            tile={tile}
            active={active?(tile, @current_path)}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :tile, :map, required: true
  attr :active, :boolean, default: false

  defp summary_row(%{tile: %{external: true}} = assigns) do
    ~H"""
    <a href={@tile.path} target="_blank" rel="noopener" class={row_class(@active)}>
      <.row_body tile={@tile} active={@active} />
    </a>
    """
  end

  defp summary_row(assigns) do
    ~H"""
    <.link navigate={@tile.path} class={row_class(@active)}>
      <.row_body tile={@tile} active={@active} />
    </.link>
    """
  end

  defp row_class(active) do
    [
      "flex items-center justify-between gap-3 px-4 py-3 border-b border-border last:border-b-0 no-underline transition-colors",
      if(active, do: "bg-accentSoft", else: "hover:bg-paperAlt")
    ]
  end

  attr :tile, :map, required: true
  attr :active, :boolean, default: false

  defp row_body(assigns) do
    ~H"""
    <span class={[
      "text-[13px] font-medium flex items-center gap-1.5",
      if(@active, do: "text-accent", else: "text-ink")
    ]}>
      {@tile.title}
      <ColtWeb.Components.Liid.icon
        :if={Map.get(@tile, :external)}
        name="link"
        size={11}
        class="text-inkFaint"
      />
      <span
        :if={Map.get(@tile, :alert)}
        class="w-1.5 h-1.5 rounded-full bg-red"
        title="needs attention"
      >
      </span>
    </span>
    <span class={[
      "text-[13px] tabular-nums shrink-0",
      cond do
        @active -> "text-accent"
        Map.get(@tile, :alert) -> "text-red font-semibold"
        true -> "text-ink55"
      end
    ]}>
      {@tile.value}
    </span>
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
      group: "System",
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
      group: "System",
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

  # Deliberately coarse — signals "an estimate, roughly this" (from reltuples),
  # not an exact count. 2_713_893 -> "~2.7M", 43_210 -> "~43k".
  defp format_approx(n) when n >= 1_000_000,
    do: "~" <> :erlang.float_to_binary(n / 1_000_000, decimals: 1) <> "M"

  defp format_approx(n) when n >= 1_000,
    do: "~" <> Integer.to_string(round(n / 1_000)) <> "k"

  defp format_approx(n), do: Integer.to_string(n)

  defp current_month_cost do
    {:ok, rows} = Colt.Services.Costs.MonthlySummary.run(1)
    ym = current_ym()

    rows
    |> Enum.filter(&(&1.month == ym))
    |> Enum.reduce(Decimal.new(0), &Decimal.add(&2, &1.cost_usd))
  end

  # Most recent month with any enriched contacts — falls back through prior
  # months since the current month may not have any yet.
  defp contact_cost_summary do
    {:ok, rows} = Colt.Services.Costs.ContactCostByMonth.run(3)

    rows
    |> Enum.filter(& &1.avg_cost_usd)
    |> List.last()
    |> case do
      nil -> "no data yet"
      row -> "$" <> format_avg(row.avg_cost_usd) <> " · " <> month_short(row.month)
    end
  end

  defp format_avg(%Decimal{} = d), do: d |> Decimal.round(4) |> Decimal.to_string(:normal)

  defp month_short(<<y::binary-size(4), "-", mm::binary-size(2)>>) do
    {:ok, date} = Date.new(String.to_integer(y), String.to_integer(mm), 1)
    Calendar.strftime(date, "%b")
  end

  # Clients and their lifetime profit now live on one page. The rollup behind it
  # is already memoized for 24h in ClientList, so reading it here is cheap.
  defp client_tile do
    {:ok, %{totals: totals}} = Colt.Services.Admin.ClientList.run()

    %{
      group: "Users",
      title: "All users",
      value: "#{format_int(totals.users)} users · #{format_signed(totals.profit)}",
      path: "/admin/clients"
    }
  end

  defp current_ym do
    %{year: y, month: m} = DateTime.utc_now()
    "#{y}-#{m |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp format_money(%Decimal{} = d) do
    "$" <> (d |> Decimal.round(2) |> Decimal.to_string(:normal))
  end

  # Profit reads as -$9.37, never $-9.37.
  defp format_signed(%Decimal{} = d) do
    sign = if Decimal.negative?(d), do: "-", else: ""
    sign <> format_money(Decimal.abs(d))
  end
end
