defmodule ColtWeb.Campaigns.FiltersLive do
  @moduledoc """
  View 3 — filters. A centered, max-width two-pane layout: a left menu
  (Markets · Size & growth · Industries) whose rows preview the actual selected
  values, and a right detail pane. Markets is a multi-select; Industries is a
  NACE tree (sections → divisions → groups → 4-digit classes) with tri-state
  checkboxes. A live counter shows how many companies match across the chosen
  markets.

  The industries form holds *node ids* (section letters / 2/3/4-digit codes);
  they are expanded to 4-digit classes only at query time (`for_query/1`), so
  the `:filtered` action is unchanged and old 4-digit saved filters still work.
  """
  use ColtWeb, :live_view

  alias Colt.Filters
  alias Colt.Filters.IndustryLabels
  alias Colt.Markets
  alias Colt.Resources.{Campaign, Company}
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  @growth_buckets [:declining, :stagnant, :slow, :growing_2x, :growing_10x]
  @panes [:markets, :size_growth, :industries]
  @debounce_ms 2_000

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        socket =
          socket
          |> assign(
            page_title: gettext("Filters — %{name}", name: campaign.name),
            campaign: campaign,
            form: default_form(campaign),
            active_pane: :markets,
            market_counts: %{},
            error: nil,
            confirming?: false,
            reload_ref: nil,
            pending?: true,
            industry_query: "",
            industry_results: [],
            industry_open: false,
            expanded: MapSet.new()
          )
          |> assign(empty_summary())

        # The summary is ~10 aggregate scans over the full registry; never run it
        # on the dead render (it would hold a pooled connection through the static
        # HTTP mount). Defer to the connected mount and run it off the mount path.
        if connected?(socket), do: send(self(), :reload)

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_event("select_pane", %{"pane" => pane}, socket) do
    {:noreply, assign(socket, active_pane: safe_pane(pane))}
  end

  def handle_event("toggle", %{"field" => field, "v" => value}, socket) do
    form = toggle_in_form(socket.assigns.form, field, value)
    {:noreply, socket |> assign(form: form) |> reload_filters_async()}
  end

  def handle_event("update_range", %{"field" => field} = params, socket) do
    {min_key, max_key, thresholds} = range_spec(field)
    cap = List.last(thresholds)

    min = params["min"] |> parse_int() |> nilify_floor()
    max = params["max"] |> parse_int() |> nilify_ceiling(cap)

    form =
      socket.assigns.form
      |> Map.put(min_key, min)
      |> Map.put(max_key, max)

    {:noreply, socket |> assign(form: form) |> reload_filters_async()}
  end

  def handle_event("update_slider", %{"field" => field} = params, socket) do
    {min_key, max_key, thresholds} = range_spec(field)
    last = length(thresholds) - 1

    min_idx = (params["min"] |> parse_int() || 0) |> max(0) |> min(last)
    max_idx = (params["max"] |> parse_int() || last) |> max(0) |> min(last)

    {min_idx, max_idx} =
      if min_idx > max_idx, do: {max_idx, min_idx}, else: {min_idx, max_idx}

    min_val = if min_idx == 0, do: nil, else: Enum.at(thresholds, min_idx)
    max_val = if max_idx == last, do: nil, else: Enum.at(thresholds, max_idx)

    form =
      socket.assigns.form
      |> Map.put(min_key, min_val)
      |> Map.put(max_key, max_val)

    {:noreply, socket |> assign(form: form) |> reload_filters_async()}
  end

  def handle_event("clear_chip", %{"field" => field, "v" => value}, socket) do
    form = remove_from_form(socket.assigns.form, field, value)
    {:noreply, socket |> assign(form: form) |> reload_filters_async()}
  end

  def handle_event("industry_search", %{"q" => q}, socket) do
    {:noreply,
     assign(socket,
       industry_query: q,
       industry_results: IndustryLabels.search(q),
       industry_open: true
     )}
  end

  def handle_event("industry_open", _, socket),
    do: {:noreply, assign(socket, industry_open: true)}

  def handle_event("industry_close", _, socket),
    do: {:noreply, assign(socket, industry_open: false, industry_query: "", industry_results: [])}

  def handle_event("industry_pick", %{"code" => code}, socket) do
    form = Map.update!(socket.assigns.form, :industries, &select_node(&1, code))

    {:noreply,
     socket
     |> assign(form: form, industry_query: "", industry_results: [], industry_open: false)
     |> reload_filters_async()}
  end

  def handle_event("industry_toggle", %{"id" => id}, socket) do
    sel = socket.assigns.form.industries

    new =
      cond do
        # Covered by a selected ancestor → the checkbox is inherited, a no-op.
        Enum.any?(sel, &(&1 != id and IndustryLabels.contains?(&1, id))) -> sel
        id in sel -> List.delete(sel, id)
        true -> select_node(sel, id)
      end

    form = Map.put(socket.assigns.form, :industries, new)
    {:noreply, socket |> assign(form: form) |> reload_filters_async()}
  end

  def handle_event("industry_expand", %{"node" => node}, socket) do
    {:noreply, assign(socket, expanded: toggle_set(socket.assigns.expanded, node))}
  end

  def handle_event("confirm", _params, socket) do
    socket = assign(socket, confirming?: true)
    campaign = socket.assigns.campaign
    filters = filter_args(socket.assigns.form)

    case Campaign.update_filters(campaign, filters, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        cond do
          # Already enriching → just save the filter change and top up. Never
          # redirect: this is an existing run, not new work.
          campaign.status == :enriching ->
            {:ok, _} = Colt.Jobs.Enrichment.Topup.schedule(campaign.id, schedule_in: 0)

            {:noreply,
             socket
             |> assign(campaign: campaign, confirming?: false)
             |> put_flash(:info, gettext("Filters updated."))}

          # Fresh campaign + no active plan → starting work needs a plan, so
          # send them to pricing rather than deeper into setup.
          not Colt.Accounts.User.paid?(socket.assigns.current_user) ->
            {:noreply, push_navigate(socket, to: ~p"/pricing")}

          true ->
            {:noreply, push_navigate(socket, to: ~p"/campaigns/#{campaign.id}/icp")}
        end

      {:error, err} ->
        {:noreply, assign(socket, error: inspect(err), confirming?: false)}
    end
  end

  def handle_info(:reload, socket), do: {:noreply, reload_filters(socket)}

  defp reload_filters_async(socket) do
    if ref = socket.assigns.reload_ref, do: Process.cancel_timer(ref)
    ref = Process.send_after(self(), :reload, @debounce_ms)
    assign(socket, reload_ref: ref, pending?: true)
  end

  defp reload_filters(socket) do
    socket = ensure_market_counts(socket)
    args = for_query(filter_args(socket.assigns.form))

    case Filters.run(args) do
      {:ok, s} ->
        assign(socket,
          count: s.count,
          total: s.total,
          bucket_totals: s.bucket_totals,
          top_industries: s.top_industries,
          last_sync: s.last_sync,
          pending?: false,
          reload_ref: nil
        )

      {:error, err} ->
        assign(socket, error: inspect(err), pending?: false, reload_ref: nil)
    end
  end

  defp ensure_market_counts(socket) do
    if map_size(socket.assigns.market_counts) == 0 do
      counts =
        case Company.market_totals() do
          {:ok, m} -> m
          _ -> %{}
        end

      assign(socket, market_counts: counts)
    else
      socket
    end
  end

  # Safe defaults so a failed (or not-yet-run) reload never leaves a summary
  # assign unset — render/1 reads all of these unconditionally.
  defp empty_summary do
    %{count: 0, total: 0, bucket_totals: %{}, top_industries: [], last_sync: nil}
  end

  defp default_form(campaign) do
    saved = campaign.filters || %{}

    %{
      markets: seed_markets(saved),
      industries: Map.get(saved, "industries", []),
      industries_exclude: Map.get(saved, "industries_exclude", []),
      growth_buckets: Map.get(saved, "growth_buckets", []) |> Enum.map(&safe_atom/1),
      employees_min: Map.get(saved, "employees_min"),
      employees_max: Map.get(saved, "employees_max"),
      revenue_min: Map.get(saved, "revenue_min"),
      revenue_max: Map.get(saved, "revenue_max")
    }
  end

  defp seed_markets(saved) do
    enabled = Markets.enabled_atoms()

    case Map.get(saved, "markets") do
      list when is_list(list) ->
        list |> Enum.map(&safe_atom/1) |> Enum.filter(&(&1 in enabled))

      _ ->
        []
    end
  end

  defp safe_atom(a) when is_atom(a), do: a

  defp safe_atom(s) when is_binary(s) do
    String.to_existing_atom(s)
  rescue
    ArgumentError -> nil
  end

  # Node ids (NOT expanded) — what's persisted and shown in the menu.
  defp filter_args(form) do
    %{
      markets: form.markets,
      industries: form.industries,
      industries_exclude: form.industries_exclude,
      growth_buckets: form.growth_buckets,
      employees_min: form.employees_min,
      employees_max: form.employees_max,
      revenue_min: form.revenue_min,
      revenue_max: form.revenue_max
    }
  end

  # Expand industry node ids to 4-digit classes for the `:filtered` action.
  defp for_query(args) do
    %{
      args
      | industries: IndustryLabels.expand_codes(args.industries),
        industries_exclude: IndustryLabels.expand_codes(args.industries_exclude)
    }
  end

  # Add `id`, dropping any already-selected descendants it now covers.
  defp select_node(selected, id),
    do: [id | Enum.reject(selected, &IndustryLabels.contains?(id, &1))]

  defp safe_pane(p) do
    atom = String.to_existing_atom(p)
    if atom in @panes, do: atom, else: :markets
  rescue
    ArgumentError -> :markets
  end

  defp toggle_set(set, value) do
    if MapSet.member?(set, value), do: MapSet.delete(set, value), else: MapSet.put(set, value)
  end

  defp toggle_in_form(form, "markets", v),
    do: Map.update!(form, :markets, &toggle(&1, String.to_existing_atom(v)))

  defp toggle_in_form(form, "growth_buckets", v),
    do: Map.update!(form, :growth_buckets, &toggle(&1, String.to_existing_atom(v)))

  defp remove_from_form(form, "industries", v),
    do: Map.update!(form, :industries, &List.delete(&1, v))

  defp toggle(list, value) do
    if value in list, do: List.delete(list, value), else: [value | list]
  end

  # field -> {min_key, max_key, threshold_list}.
  # Slider thumbs snap to indices in the list; the last value is the cap
  # ("X+", stored as nil = unbounded). The number inputs accept any integer.
  defp range_spec("employees"),
    do:
      {:employees_min, :employees_max, [0, 5, 10, 20, 30, 50, 75, 100, 150, 200, 300, 500, 1_000]}

  defp range_spec("revenue"),
    do:
      {:revenue_min, :revenue_max,
       [
         0,
         50_000,
         100_000,
         250_000,
         500_000,
         1_000_000,
         2_500_000,
         5_000_000,
         10_000_000,
         25_000_000,
         50_000_000,
         100_000_000
       ]}

  # 0 (or nothing) → no lower bound
  defp nilify_floor(nil), do: nil
  defp nilify_floor(0), do: nil
  defp nilify_floor(n), do: n

  # at-cap → no upper bound
  defp nilify_ceiling(nil, _), do: nil
  defp nilify_ceiling(n, cap) when n >= cap, do: nil
  defp nilify_ceiling(n, _), do: n

  defp parse_int(nil), do: nil
  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case String.replace(s, ~r/[^0-9]/, "") do
      "" -> nil
      digits -> String.to_integer(digits)
    end
  end

  # ── menu / summaries ──────────────────────────────────────────────────────

  defp menu_items do
    [{:markets, gettext("Markets")}, {:size_growth, gettext("Size & growth")},
     {:industries, gettext("Industries")}]
  end

  # Each summary is a list of lines (or nil) — the menu stacks them vertically.
  defp pane_summary(:markets, form) do
    case form.markets do
      [] -> nil
      ms -> Enum.map(ms, &market_name/1)
    end
  end

  defp pane_summary(:size_growth, form) do
    [
      range_phrase(form.employees_min, form.employees_max, :int, gettext("emp")),
      range_phrase(form.revenue_min, form.revenue_max, :money, nil)
      | growth_lines(form.growth_buckets)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> parts
    end
  end

  defp pane_summary(:industries, form) do
    case form.industries do
      [] -> nil
      ids -> Enum.map(ids, &IndustryLabels.node_label/1)
    end
  end

  defp range_phrase(nil, nil, _, _), do: nil

  defp range_phrase(min, max, fmt, unit) do
    base = range_hint(min, max, nil, fmt)
    if unit, do: "#{base} #{unit}", else: base
  end

  defp growth_lines(buckets), do: Enum.map(buckets, &growth_label/1)

  defp market_name(m) do
    case Enum.find(Markets.all(), &(&1.market == m)) do
      %{name: n} -> n
      _ -> m |> Atom.to_string() |> String.upcase()
    end
  end

  defp market_count_label(counts, market) do
    case Map.get(counts, market) do
      nil -> "—"
      n -> format_int(n)
    end
  end

  # ── industry tree ─────────────────────────────────────────────────────────

  defp visible_industry_rows(expanded) do
    Enum.flat_map(IndustryLabels.sections(), fn {letter, title} ->
      [
        %{level: 0, id: letter, code: letter, label: title, leaf?: false}
        | rows_if_open(expanded, letter, fn ->
            Enum.flat_map(IndustryLabels.divisions_for_section(letter), fn {d, dl} ->
              [
                %{level: 1, id: d, code: d, label: dl, leaf?: false}
                | rows_if_open(expanded, d, fn ->
                    Enum.flat_map(IndustryLabels.groups_for_division(d), fn {g, gl} ->
                      [
                        %{level: 2, id: g, code: g, label: gl, leaf?: false}
                        | rows_if_open(expanded, g, fn ->
                            Enum.map(IndustryLabels.classes_for_group(g), fn {c, cl} ->
                              %{level: 3, id: c, code: c, label: cl, leaf?: true}
                            end)
                          end)
                      ]
                    end)
                  end)
              ]
            end)
          end)
      ]
    end)
  end

  defp rows_if_open(expanded, node, fun),
    do: if(MapSet.member?(expanded, node), do: fun.(), else: [])

  defp industry_node_state(id, selected) do
    cond do
      id in selected -> :checked
      Enum.any?(selected, &(&1 != id and IndustryLabels.contains?(&1, id))) -> :inherited
      Enum.any?(selected, &IndustryLabels.contains?(id, &1)) -> :partial
      true -> :none
    end
  end

  defp node_text_size(0), do: "text-[13px] font-semibold"
  defp node_text_size(1), do: "text-[12.5px] font-medium"
  defp node_text_size(_), do: "text-[12px]"

  # ── formatting ────────────────────────────────────────────────────────────

  defp range_hint(nil, nil, _, _), do: nil
  defp range_hint(min, nil, _, fmt), do: "#{fmt_n(min, fmt)}+"
  defp range_hint(nil, max, _, fmt), do: "≤ #{fmt_n(max, fmt)}"
  defp range_hint(min, max, _, fmt), do: "#{fmt_n(min, fmt)} – #{fmt_n(max, fmt)}"

  defp nearest_index(value, thresholds) do
    thresholds
    |> Enum.with_index()
    |> Enum.min_by(fn {t, _i} -> abs(t - value) end)
    |> elem(1)
  end

  defp fmt_n(n, :int), do: format_int(n)
  defp fmt_n(n, :money), do: format_money(n)

  defp format_money(n) when is_integer(n) and n >= 1_000_000,
    do: "€#{format_decimal(n / 1_000_000, 1)}M"

  defp format_money(n) when is_integer(n) and n >= 1_000,
    do: "€#{div(n, 1_000)}k"

  defp format_money(n) when is_integer(n), do: "€#{n}"
  defp format_money(_), do: "—"

  defp format_decimal(f, places) do
    :io_lib.format("~.#{places}f", [f]) |> IO.iodata_to_binary() |> trim_zero()
  end

  defp trim_zero(s) do
    if String.contains?(s, ".") do
      s |> String.trim_trailing("0") |> String.trim_trailing(".")
    else
      s
    end
  end

  defp format_int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.codepoints()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_int(_), do: "—"

  defp format_grouped(nil), do: ""
  defp format_grouped(n) when is_integer(n), do: format_int(n)

  defp confirm_label(:enriching), do: gettext("Save filters")
  defp confirm_label(_), do: gettext("Continue → ICP")

  defp growth_label(:growing_10x), do: gettext("Growing · 10×")
  defp growth_label(:growing_2x), do: gettext("Growing · 2×")
  defp growth_label(:slow), do: gettext("Growing · slow")
  defp growth_label(:stagnant), do: gettext("Stagnant")
  defp growth_label(:declining), do: gettext("Shrinking")
  defp growth_label(_), do: "—"

  # ── render ────────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      step={3}
      campaign={@campaign}
      campaign_name={@campaign.name}
      campaign_id={@campaign.id}
    >
      <div class="w-full max-w-[900px] mx-auto flex flex-col gap-5 flex-1 min-h-0">
        <.counter_bar
          count={@count}
          total={@total}
          pending?={@pending?}
          has_markets?={@form.markets != []}
          status={@campaign.status}
          confirming?={@confirming?}
          error={@error}
        />

        <div class="flex flex-col lg:flex-row gap-5 flex-1 min-h-0">
          <.filter_menu form={@form} active_pane={@active_pane} />

          <div class="flex-1 min-h-0 overflow-auto">
            <.markets_pane
              :if={@active_pane == :markets}
              form={@form}
              market_counts={@market_counts}
            />
            <.size_growth_pane
              :if={@active_pane == :size_growth}
              form={@form}
              bucket_totals={@bucket_totals}
            />
            <.industries_pane
              :if={@active_pane == :industries}
              form={@form}
              expanded={@expanded}
              industry_query={@industry_query}
              industry_results={@industry_results}
              industry_open={@industry_open}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :count, :integer, required: true
  attr :total, :integer, required: true
  attr :pending?, :boolean, required: true
  attr :has_markets?, :boolean, required: true
  attr :status, :atom, required: true
  attr :confirming?, :boolean, required: true
  attr :error, :string, default: nil

  defp counter_bar(assigns) do
    ~H"""
    <div class="bg-accentSoft border border-accentRing rounded-[11px] [box-shadow:0_0_0_1px_var(--accentRing),var(--shadow-card)] p-5 md:p-6 flex flex-col sm:flex-row sm:items-center gap-4">
      <div class="flex-1 min-w-0">
        <div class="text-[10px] tracking-[0.12em] uppercase text-accent font-semibold mb-2 flex items-center gap-2">
          {gettext("Companies match")}
          <span
            :if={@pending?}
            class="relative w-1.5 h-1.5 rounded-full"
            style="background: var(--accent);"
          >
            <span
              class="absolute inset-0 rounded-full animate-[pulse-halo_1.4s_ease-out_infinite]"
              style="background: var(--accent);"
            />
          </span>
        </div>
        <div :if={@has_markets?} class="flex items-baseline gap-3">
          <div class={[
            "text-[44px] md:text-[56px] font-bold leading-[0.9] tnum tracking-[-0.02em] transition-opacity text-accent",
            @pending? && "opacity-40"
          ]}>
            {format_int(@count)}
          </div>
          <div class="text-[12px] text-inkSoft tnum pb-1">
            {gettext("of %{n}", n: format_int(@total))}
          </div>
        </div>
        <div :if={not @has_markets?} class="text-[13px] text-inkSoft">
          {gettext("Pick at least one market to see matching companies.")}
        </div>
        <div :if={@error} class="mt-2 text-[11px] text-red">{@error}</div>
      </div>
      <div class="flex items-center gap-3 shrink-0">
        <.link
          navigate={~p"/campaigns"}
          class="inline-flex items-center gap-2 px-3.5 py-[7px] text-[12px] font-semibold border border-borderStrong bg-card rounded-[8px] no-underline text-inkSoft hover:bg-paperAlt hover:text-ink [box-shadow:var(--shadow)]"
        >
          <Liid.icon name="chev-l" size={11} /> {gettext("Back")}
        </.link>
        <Liid.btn variant={:primary} phx-click="confirm" disabled={@confirming? or @count == 0}>
          {confirm_label(@status)}
        </Liid.btn>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :active_pane, :atom, required: true

  defp filter_menu(assigns) do
    ~H"""
    <div class="lg:basis-[280px] lg:shrink-0 self-start bg-card border border-border rounded-[11px] [box-shadow:var(--shadow-card)] flex flex-col gap-1 p-2">
      <%= for {pane, label} <- menu_items() do %>
        <% active = @active_pane == pane %>
        <% summary = pane_summary(pane, @form) %>
        <button
          type="button"
          phx-click="select_pane"
          phx-value-pane={pane}
          class={[
            "w-full text-left flex flex-col gap-1 px-3 py-2.5 rounded-[8px] border cursor-pointer transition-all",
            active && "bg-accentSoft border-accentRing",
            not active && "border-transparent hover:bg-paperAlt"
          ]}
        >
          <span class={[
            "text-[10px] tracking-[0.1em] uppercase font-semibold",
            active && "text-accent",
            not active && "text-inkFaint"
          ]}>
            {label}
          </span>
          <div :if={summary} class="flex flex-col gap-0.5">
            <span :for={line <- summary} class="text-[12px] leading-snug text-ink">{line}</span>
          </div>
          <span :if={is_nil(summary)} class="text-[12px] leading-snug text-inkFaint italic">
            {gettext("Any")}
          </span>
        </button>
      <% end %>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :hint, :string, default: nil
  slot :inner_block, required: true

  defp pane(assigns) do
    ~H"""
    <div class="bg-card border border-border rounded-[11px] [box-shadow:var(--shadow-card)] p-5 md:p-6">
      <div class="flex items-baseline gap-2 mb-4">
        <h2 class="text-[15px] font-semibold text-ink">{@title}</h2>
        <span :if={@hint} class="text-[11px] text-inkFaint">{@hint}</span>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :form, :map, required: true
  attr :market_counts, :map, required: true

  defp markets_pane(assigns) do
    ~H"""
    <.pane title={gettext("Markets")} hint={gettext("registries to pull companies from")}>
      <div class="flex flex-col gap-1">
        <%= for m <- Markets.enabled() do %>
          <% on = m.market in @form.markets %>
          <button
            type="button"
            phx-click="toggle"
            phx-value-field="markets"
            phx-value-v={m.market}
            class={[
              "flex items-center gap-3 px-3 py-2.5 cursor-pointer text-left rounded-[8px] border",
              on && "bg-accentSoft border-accentRing",
              not on && "border-transparent hover:bg-paperAlt"
            ]}
          >
            <.checkbox checked={on} />
            <span class="text-[11px] text-inkFaint tnum w-6 shrink-0 font-semibold">{m.code}</span>
            <span class={[
              "text-[13px] flex-1",
              on && "text-accent font-medium",
              not on && "text-ink"
            ]}>
              {m.name}
            </span>
            <span class="text-[11px] text-inkFaint tnum">
              {market_count_label(@market_counts, m.market)}
            </span>
          </button>
        <% end %>
      </div>
    </.pane>
    """
  end

  attr :form, :map, required: true
  attr :bucket_totals, :map, required: true

  defp size_growth_pane(assigns) do
    assigns = assign(assigns, growth_buckets: @growth_buckets)

    ~H"""
    <.pane title={gettext("Size & growth")} hint={gettext("most recent annual filing")}>
      <div class="flex flex-col gap-7">
        <div>
          <.sub_label>{gettext("Employees")}</.sub_label>
          <.range_fset field="employees" min={@form.employees_min} max={@form.employees_max} format={:int} />
        </div>

        <div>
          <.sub_label>{gettext("Revenue (€)")}</.sub_label>
          <.range_fset field="revenue" min={@form.revenue_min} max={@form.revenue_max} format={:money} />
        </div>

        <div>
          <.sub_label>
            {gettext("Growth")}
            <span class="text-inkFaint normal-case tracking-normal font-normal ml-1">
              {gettext("· revenue Δ over 3 fiscal years")}
            </span>
          </.sub_label>
          <div class="flex flex-col gap-1">
            <%= for bucket <- @growth_buckets do %>
              <% on = bucket in @form.growth_buckets %>
              <button
                type="button"
                phx-click="toggle"
                phx-value-field="growth_buckets"
                phx-value-v={bucket}
                class={[
                  "flex items-center gap-2.5 px-2.5 py-2 cursor-pointer text-left rounded-[8px] border",
                  on && "bg-accentSoft border-accentRing",
                  not on && "border-transparent hover:bg-paperAlt"
                ]}
              >
                <.checkbox checked={on} />
                <span class={[
                  "text-[13px] flex-1",
                  on && "text-accent font-medium",
                  not on && "text-ink"
                ]}>
                  {growth_label(bucket)}
                </span>
                <span class="text-[11px] text-inkFaint tnum">
                  {Map.get(@bucket_totals, bucket, 0)}
                </span>
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </.pane>
    """
  end

  slot :inner_block, required: true

  defp sub_label(assigns) do
    ~H"""
    <div class="text-[11px] tracking-[0.08em] uppercase text-inkSoft font-semibold mb-3">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :form, :map, required: true
  attr :expanded, :any, required: true
  attr :industry_query, :string, required: true
  attr :industry_results, :list, required: true
  attr :industry_open, :boolean, required: true

  defp industries_pane(assigns) do
    ~H"""
    <.pane title={gettext("Industries")} hint={gettext("pick a category or drill in")}>
      <div class="flex flex-col gap-3">
        <.industry_search
          query={@industry_query}
          results={@industry_results}
          open={@industry_open}
        />
        <.selected_industries selected={@form.industries} />
        <.industry_tree
          rows={visible_industry_rows(@expanded)}
          selected={@form.industries}
          expanded={@expanded}
        />
      </div>
    </.pane>
    """
  end

  attr :field, :string, required: true
  attr :min, :any, default: nil
  attr :max, :any, default: nil
  attr :format, :atom, default: :int, values: [:int, :money]

  defp range_fset(assigns) do
    {_min_key, _max_key, thresholds} = range_spec(assigns.field)
    last_idx = length(thresholds) - 1
    cap = List.last(thresholds)

    min_idx = if assigns.min, do: nearest_index(assigns.min, thresholds), else: 0
    max_idx = if assigns.max, do: nearest_index(assigns.max, thresholds), else: last_idx

    assigns =
      assign(assigns,
        cap: cap,
        last_idx: last_idx,
        min_idx: min_idx,
        max_idx: max_idx,
        min_pct: min_idx / last_idx * 100,
        max_pct: max_idx / last_idx * 100
      )

    ~H"""
    <div>
      <div class="flex justify-end mb-2">
        <span class="text-[11px] text-inkSoft tnum">
          {range_hint(@min, @max, @cap, @format) || gettext("any")}
        </span>
      </div>

      <form id={"slider-form-#{@field}"} phx-change="update_slider" class="space-y-3">
        <input type="hidden" name="field" value={@field} />

        <div class="relative h-5 mx-2">
          <div class="absolute left-0 right-0 top-1/2 -translate-y-1/2 h-[5px] rounded-full bg-border" />
          <div
            class="absolute top-1/2 -translate-y-1/2 h-[5px] rounded-full"
            style={"left: #{@min_pct}%; right: #{100 - @max_pct}%; background: var(--accent);"}
          />
          <input
            type="range"
            name="min"
            min="0"
            max={@last_idx}
            step="1"
            value={@min_idx}
            class="liid-range"
            style="z-index: 2;"
            phx-debounce="100"
          />
          <input
            type="range"
            name="max"
            min="0"
            max={@last_idx}
            step="1"
            value={@max_idx}
            class="liid-range"
            style="z-index: 1;"
            phx-debounce="100"
          />
        </div>
      </form>

      <form id={"range-form-#{@field}"} phx-change="update_range" class="flex gap-2 mt-2">
        <input type="hidden" name="field" value={@field} />
        <input
          type="text"
          id={"range-min-#{@field}"}
          inputmode="numeric"
          name="min"
          value={format_grouped(@min)}
          placeholder={gettext("min")}
          phx-debounce="600"
          class="flex-1 min-w-0 px-2.5 py-1.5 border border-border bg-card text-[12px] tnum rounded-[8px] outline-none focus:border-accentRing focus:[box-shadow:inset_0_0_0_1px_var(--accentRing)]"
        />
        <span class="self-center text-inkFaint">—</span>
        <input
          type="text"
          id={"range-max-#{@field}"}
          inputmode="numeric"
          name="max"
          value={format_grouped(@max)}
          placeholder={gettext("max")}
          phx-debounce="600"
          class="flex-1 min-w-0 px-2.5 py-1.5 border border-border bg-card text-[12px] tnum rounded-[8px] outline-none focus:border-accentRing focus:[box-shadow:inset_0_0_0_1px_var(--accentRing)]"
        />
      </form>
    </div>
    """
  end

  attr :checked, :boolean, required: true

  defp checkbox(assigns) do
    ~H"""
    <span class={[
      "w-3.5 h-3.5 border flex items-center justify-center rounded-[4px] shrink-0",
      @checked && "border-accent bg-accent",
      not @checked && "border-borderStrong bg-card"
    ]}>
      <Liid.icon :if={@checked} name="check" size={9} class="text-white" />
    </span>
    """
  end

  attr :state, :atom, required: true

  defp tri_checkbox(assigns) do
    ~H"""
    <span class={[
      "w-3.5 h-3.5 border flex items-center justify-center rounded-[4px] shrink-0",
      @state in [:checked, :inherited] && "border-accent bg-accent",
      @state == :partial && "border-accentRing bg-accentSoft",
      @state == :none && "border-borderStrong bg-card"
    ]}>
      <Liid.icon :if={@state in [:checked, :inherited]} name="check" size={9} class="text-white" />
      <span
        :if={@state == :partial}
        class="w-1.5 h-[2px] rounded-full"
        style="background: var(--accent);"
      />
    </span>
    """
  end

  attr :query, :string, required: true
  attr :results, :list, required: true
  attr :open, :boolean, required: true

  defp industry_search(assigns) do
    ~H"""
    <div class="relative" phx-click-away="industry_close">
      <form id="industry-search-form" phx-change="industry_search" autocomplete="off">
        <input
          type="text"
          id="industry-search-input"
          name="q"
          value={@query}
          placeholder={gettext("search industries…")}
          phx-focus="industry_open"
          phx-debounce="150"
          class="w-full px-3 py-2 border border-border bg-card text-[12px] text-ink rounded-[8px] outline-none placeholder:text-inkFaint [box-shadow:var(--shadow)] focus:border-accentRing focus:[box-shadow:inset_0_0_0_1px_var(--accentRing)]"
        />
      </form>

      <div
        :if={@open and @query != ""}
        class="absolute z-10 left-0 right-0 top-full mt-1.5 bg-card border border-border rounded-[8px] [box-shadow:var(--shadow-card)] max-h-[280px] overflow-auto"
      >
        <div :if={@results == []} class="px-3 py-2.5 text-[11px] text-inkFaint">
          {gettext("no matches")}
        </div>
        <%= for {code, en} <- @results do %>
          <button
            type="button"
            phx-click="industry_pick"
            phx-value-code={code}
            class="w-full text-left px-3 py-2 flex items-baseline gap-2 border-b border-border last:border-b-0 hover:bg-accentSoft cursor-pointer"
          >
            <span class="text-[10px] text-inkFaint tnum w-9 shrink-0">{code}</span>
            <span class="text-[12px] text-ink truncate flex-1">{en}</span>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  attr :selected, :list, required: true

  defp selected_industries(assigns) do
    ~H"""
    <div :if={@selected != []} class="flex flex-wrap gap-1.5">
      <%= for id <- @selected do %>
        <span class="inline-flex items-center gap-1.5 pl-2.5 pr-1.5 py-1 text-[11px] bg-accentSoft text-accent border border-accentRing rounded-[8px]">
          {IndustryLabels.node_label(id)}
          <button
            type="button"
            phx-click="clear_chip"
            phx-value-field="industries"
            phx-value-v={id}
            class="text-accent/70 hover:text-accent cursor-pointer"
          >
            <Liid.icon name="x" size={9} />
          </button>
        </span>
      <% end %>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :selected, :list, required: true
  attr :expanded, :any, required: true

  defp industry_tree(assigns) do
    ~H"""
    <div class="border border-border rounded-[8px] max-h-[440px] overflow-auto bg-bgSoft">
      <%= for row <- @rows do %>
        <% state = industry_node_state(row.id, @selected) %>
        <% open = MapSet.member?(@expanded, row.id) %>
        <div
          class="flex items-center gap-1.5 py-1 pr-2 border-b border-border/60 last:border-b-0 hover:bg-paperAlt"
          style={"padding-left: #{8 + row.level * 18}px;"}
        >
          <button
            :if={not row.leaf?}
            type="button"
            phx-click="industry_expand"
            phx-value-node={row.id}
            class="w-4 h-4 flex items-center justify-center text-inkFaint hover:text-ink cursor-pointer shrink-0"
          >
            <Liid.icon name={if open, do: "chev", else: "chev-r"} size={11} />
          </button>
          <span :if={row.leaf?} class="w-4 shrink-0" />

          <button
            type="button"
            phx-click="industry_toggle"
            phx-value-id={row.id}
            disabled={state == :inherited}
            class="shrink-0 disabled:cursor-not-allowed cursor-pointer"
          >
            <.tri_checkbox state={state} />
          </button>

          <button
            type="button"
            phx-click={if row.leaf?, do: "industry_toggle", else: "industry_expand"}
            phx-value-id={row.id}
            phx-value-node={row.id}
            class="flex items-baseline gap-2 text-left flex-1 min-w-0 cursor-pointer py-0.5"
          >
            <span :if={row.level > 0} class="text-[10px] text-inkFaint tnum shrink-0">
              {row.code}
            </span>
            <span class={[
              node_text_size(row.level),
              "truncate",
              state in [:checked, :inherited] && "text-accent",
              state not in [:checked, :inherited] && "text-ink"
            ]}>
              {row.label}
            </span>
          </button>
        </div>
      <% end %>
    </div>
    """
  end
end
