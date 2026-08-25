defmodule ColtWeb.Admin.IndustriesLive do
  @moduledoc """
  `/admin/industries` — which industries are growing, so we can point the
  product at the ones that are.

  The same collapsible NACE tree the campaign filters use, but every node
  carries growth instead of a checkbox: section → division → group → 4-digit
  class, each row sorted fastest-growing first. `Colt.Services.Admin.IndustryGrowth`
  owns the arithmetic and documents the cohort rules; this module only lays it out.
  """
  use ColtWeb, :live_view

  alias Colt.Filters.IndustryLabels
  alias Colt.Markets
  alias Colt.Services.Admin.IndustryGrowth
  alias ColtWeb.Components.{AdminFormat, Liid}

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  @default_market :ee

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(expanded: MapSet.new()) |> load(@default_market)}
  end

  def handle_event("market", %{"market" => value}, socket) do
    market = Enum.find(Markets.atoms(), &(to_string(&1) == value)) || @default_market

    {:noreply, socket |> assign(expanded: MapSet.new()) |> load(market)}
  end

  def handle_event("toggle", %{"node" => node}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, node),
        do: MapSet.delete(expanded, node),
        else: MapSet.put(expanded, node)

    {:noreply, assign(socket, expanded: expanded)}
  end

  def handle_event("collapse_all", _params, socket),
    do: {:noreply, assign(socket, expanded: MapSet.new())}

  defp load(socket, market),
    do: assign(socket, market: market, data: IndustryGrowth.load(market))

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <div class="flex items-start justify-between gap-6 flex-wrap">
          <div class="space-y-3 max-w-[70ch]">
            <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">
              Industry <em>growth</em>
            </h1>
            <p class="text-[13px] text-ink70">
              Revenue growth per industry, {@data.base_year} → {@data.latest_year}, from filed
              annual reports. A company counts only where it filed revenue in <strong>both</strong>
              years and made at least {AdminFormat.eur_compact(IndustryGrowth.min_revenue_eur())} in
              {@data.latest_year} — so this is like-for-like growth of real companies, not
              filing churn. Expand a section to see its divisions, groups and 4-digit classes.
            </p>
          </div>

          <form phx-change="market" class="shrink-0">
            <label
              for="industry-market"
              class="block text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-1.5"
            >
              Country
            </label>
            <select
              id="industry-market"
              name="market"
              class="border border-border rounded-[8px] bg-card px-3 py-2 text-[13px] text-ink cursor-pointer"
            >
              <option
                :for={m <- Markets.all()}
                value={m.market}
                selected={m.market == @market}
              >
                {Markets.label(m.market)}
              </option>
            </select>
          </form>
        </div>

        <.no_data :if={is_nil(@data.market_total)} data={@data} market={@market} />

        <div :if={@data.market_total} class="space-y-6">
          <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
            <AdminFormat.stat
              label="market growth"
              value={pct(@data.market_total.total_ratio)}
              sub={multiple_sub(@data.market_total.total_ratio, "all industries combined")}
              class={growth_class(@data.market_total.total_ratio)}
            />
            <AdminFormat.stat
              label="typical company"
              value={pct(@data.market_total.median_ratio)}
              sub={multiple_sub(@data.market_total.median_ratio, "median company")}
              class={growth_class(@data.market_total.median_ratio)}
            />
            <AdminFormat.stat
              label={"revenue · #{@data.latest_year}"}
              value={AdminFormat.eur_compact(@data.market_total.latest_total)}
              sub={"#{AdminFormat.eur_change(@data.market_total.change)} vs #{@data.base_year}"}
            />
            <AdminFormat.stat
              label="companies compared"
              value={AdminFormat.int(@data.market_total.companies)}
              sub={"filed both #{@data.base_year} and #{@data.latest_year}"}
            />
          </div>

          <div class="flex items-center justify-between gap-4">
            <p class="text-[11.5px] text-ink55">
              Sorted fastest-growing first, at every level. Industries with fewer than
              {IndustryGrowth.min_companies()} companies show their count but no growth —
              too few to mean anything — and still count toward their parent.
            </p>
            <button
              type="button"
              phx-click="collapse_all"
              class="border border-border rounded-[8px] px-3 py-1.5 text-[11px] font-semibold text-ink70 hover:bg-paperAlt cursor-pointer shrink-0"
            >
              Collapse all
            </button>
          </div>

          <div
            class="border border-border rounded-[11px] bg-card overflow-x-auto"
            style="box-shadow:var(--shadow-card)"
          >
            <table class="w-full text-[13px]">
              <thead>
                <tr class="text-left text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55 bg-paperAlt border-b border-border">
                  <th class="px-3 py-2 min-w-[320px]">Industry</th>
                  <th class="px-3 py-2 text-right">Growth</th>
                  <th class="px-3 py-2 text-right">Typical company</th>
                  <th class="px-3 py-2 text-right">Companies</th>
                  <th class="px-3 py-2 text-right">{@data.base_year}</th>
                  <th class="px-3 py-2 text-right">{@data.latest_year}</th>
                  <th class="px-3 py-2 text-right">Change</th>
                  <th class="px-3 py-2 text-right">Share</th>
                </tr>
              </thead>
              <tbody>
                <.row :for={row <- visible_rows(@data.nodes, @expanded)} row={row} expanded={@expanded} />
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :row, :map, required: true
  attr :expanded, :any, required: true

  defp row(assigns) do
    ~H"""
    <tr class="border-b border-border last:border-b-0 hover:bg-paperAlt">
      <td class="px-3 py-1.5" style={"padding-left: #{12 + @row.level * 18}px;"}>
        <div class="flex items-baseline gap-2">
          <button
            :if={not @row.leaf?}
            type="button"
            phx-click="toggle"
            phx-value-node={@row.id}
            class="w-4 shrink-0 text-inkFaint hover:text-ink cursor-pointer self-center"
          >
            <Liid.icon name={if MapSet.member?(@expanded, @row.id), do: "chev", else: "chev-r"} size={11} />
          </button>
          <span :if={@row.leaf?} class="w-4 shrink-0" />
          <span :if={@row.level > 0} class="text-[10px] text-inkFaint tnum shrink-0 w-9">
            {@row.id}
          </span>
          <span class={node_text_size(@row.level)}>{@row.label}</span>
        </div>
      </td>
      <.growth_cell ratio={field(@row, :total_ratio)} strong={true} />
      <.growth_cell ratio={field(@row, :median_ratio)} strong={false} />
      <td class="px-3 py-1.5 text-right tabular-nums text-ink70">{companies(@row)}</td>
      <td class="px-3 py-1.5 text-right tabular-nums text-ink70">
        {AdminFormat.eur_compact(field(@row, :base_total))}
      </td>
      <td class="px-3 py-1.5 text-right tabular-nums text-ink70">
        {AdminFormat.eur_compact(field(@row, :latest_total))}
      </td>
      <td class="px-3 py-1.5 text-right tabular-nums text-ink70">
        {AdminFormat.eur_change(field(@row, :change))}
      </td>
      <td class="px-3 py-1.5 text-right tabular-nums text-ink55">{share(@row)}</td>
    </tr>
    """
  end

  attr :ratio, :any, required: true
  attr :strong, :boolean, required: true

  # Percentage first, multiple beside it — "+218%" answers "how fast", "3.2×"
  # answers "how much", and past a couple of hundred percent only the second
  # one is holdable in your head.
  defp growth_cell(assigns) do
    ~H"""
    <td class={[
      "px-3 py-1.5 text-right tabular-nums whitespace-nowrap",
      @strong && "font-semibold",
      growth_class(@ratio)
    ]}>
      {pct(@ratio)}
      <span :if={multiple(@ratio)} class="text-[11px] font-normal text-ink55 ml-1">
        {multiple(@ratio)}
      </span>
    </td>
    """
  end

  attr :data, :map, required: true
  attr :market, :atom, required: true

  defp no_data(assigns) do
    ~H"""
    <div class="border border-border rounded-[11px] bg-card p-6 space-y-3" style="box-shadow:var(--shadow-card)">
      <div class="text-[14px] font-semibold text-ink">
        No {@data.latest_year} filings to compare in {Markets.label(@market)}
      </div>
      <p class="text-[13px] text-ink70 max-w-[64ch]">
        Growth needs companies that filed revenue in both {@data.base_year} and
        {@data.latest_year}. Nothing in this market qualifies yet — registries publish
        a year's reports over the months that follow it, so the newest year fills in late.
      </p>
      <p :if={@data.years_available != []} class="text-[12px] text-ink55">
        Revenue on file:
        <span :for={{year, count} <- @data.years_available} class="tnum">
          {year} ({AdminFormat.int(count)}) &nbsp;
        </span>
      </p>
      <p :if={@data.years_available == []} class="text-[12px] text-ink55">
        No annual reports carry revenue for this market at all yet.
      </p>
    </div>
    """
  end

  # ── rows ──────────────────────────────────────────────────────────────────

  # The full tree, always — a node with no companies is a finding too, so it
  # keeps its row and shows dashes rather than disappearing.
  defp visible_rows(nodes, expanded),
    do: IndustryLabels.sections() |> tree_rows(0, nodes, expanded)

  defp tree_rows(children, level, nodes, expanded) do
    children
    |> Enum.map(fn {id, label} ->
      %{id: id, level: level, label: label, leaf?: level == 3, metrics: Map.get(nodes, id)}
    end)
    |> Enum.sort_by(&sort_key/1)
    |> Enum.flat_map(fn row ->
      if not row.leaf? and MapSet.member?(expanded, row.id) do
        [row | tree_rows(children_of(row), level + 1, nodes, expanded)]
      else
        [row]
      end
    end)
  end

  defp children_of(%{level: 0, id: id}), do: IndustryLabels.divisions_for_section(id)
  defp children_of(%{level: 1, id: id}), do: IndustryLabels.groups_for_division(id)
  defp children_of(%{level: 2, id: id}), do: IndustryLabels.classes_for_group(id)

  # Fastest first, then the ones too thin to rank (biggest sample first), then
  # the empty ones in code order.
  defp sort_key(%{metrics: %{total_ratio: r}}) when is_float(r), do: {0, -r, ""}
  defp sort_key(%{metrics: %{companies: n}}), do: {1, -n, ""}
  defp sort_key(%{id: id}), do: {2, 0, id}

  defp field(%{metrics: nil}, _key), do: nil
  defp field(%{metrics: metrics}, key), do: Map.fetch!(metrics, key)

  defp companies(%{metrics: nil}), do: "—"
  defp companies(%{metrics: %{companies: n}}), do: AdminFormat.int(n)

  defp share(%{metrics: nil}), do: "—"
  defp share(%{metrics: %{share: nil}}), do: "—"

  defp share(%{metrics: %{share: s}}),
    do: :erlang.float_to_binary(s * 100, decimals: 1) <> "%"

  # ── formatting ────────────────────────────────────────────────────────────

  # Percent change is the headline ("+218%"); the multiple sits beside it
  # because past a point a multiple is the easier thing to hold in your head.
  defp pct(nil), do: "—"

  defp pct(ratio) do
    change = (ratio - 1) * 100
    decimals = if abs(change) >= 10, do: 0, else: 1
    sign = if change > 0, do: "+", else: ""

    sign <> :erlang.float_to_binary(change, decimals: decimals) <> "%"
  end

  # The multiple reads as a caption beside the percentage; a node with no
  # figure just gets the caption's tail.
  defp multiple_sub(nil, suffix), do: suffix
  defp multiple_sub(ratio, suffix), do: multiple(ratio) <> " · " <> suffix

  defp multiple(nil), do: nil

  defp multiple(ratio) do
    decimals =
      cond do
        ratio >= 10 -> 0
        ratio >= 1 -> 1
        true -> 2
      end

    :erlang.float_to_binary(ratio, decimals: decimals) <> "×"
  end

  # A few percent either way is noise in registry data, not a trend.
  defp growth_class(nil), do: "text-inkFaint"
  defp growth_class(ratio) when ratio > 1.05, do: "text-green"
  defp growth_class(ratio) when ratio < 0.95, do: "text-red"
  defp growth_class(_ratio), do: "text-ink70"

  defp node_text_size(0), do: "text-[13px] font-semibold text-ink"
  defp node_text_size(1), do: "text-[12.5px] font-medium text-ink"
  defp node_text_size(_level), do: "text-[12px] text-ink70"
end
