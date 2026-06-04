defmodule ColtWeb.Campaigns.FiltersLive do
  @moduledoc """
  View 3 — filter panel + live counter + 100-row preview + confirm.
  """
  use ColtWeb, :live_view

  alias Colt.Filters
  alias Colt.Resources.Campaign
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  # TODO i18n: module attr label — rendered via growth_label/1 at render time
  @growth_buckets [
    :declining,
    :stagnant,
    :slow,
    :growing_2x,
    :growing_10x
  ]

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
            error: nil,
            confirming?: false,
            reload_ref: nil,
            pending?: false,
            industry_query: "",
            industry_results: [],
            industry_open: false,
            exclude_query: "",
            exclude_results: [],
            exclude_open: false
          )
          |> reload_filters()

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
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
       industry_results: Colt.Filters.IndustryLabels.search(q),
       industry_open: true
     )}
  end

  def handle_event("industry_open", _, socket),
    do: {:noreply, assign(socket, industry_open: true)}

  def handle_event("industry_close", _, socket),
    do: {:noreply, assign(socket, industry_open: false, industry_query: "", industry_results: [])}

  def handle_event("industry_pick", %{"code" => code}, socket) do
    form = Map.update!(socket.assigns.form, :industries, &add_unique(&1, code))

    {:noreply,
     socket
     |> assign(form: form, industry_query: "", industry_results: [], industry_open: false)
     |> reload_filters_async()}
  end

  def handle_event("exclude_search", %{"q" => q}, socket) do
    {:noreply,
     assign(socket,
       exclude_query: q,
       exclude_results: Colt.Filters.IndustryLabels.search(q),
       exclude_open: true
     )}
  end

  def handle_event("exclude_open", _, socket),
    do: {:noreply, assign(socket, exclude_open: true)}

  def handle_event("exclude_close", _, socket),
    do: {:noreply, assign(socket, exclude_open: false, exclude_query: "", exclude_results: [])}

  def handle_event("exclude_pick", %{"code" => code}, socket) do
    form = Map.update!(socket.assigns.form, :industries_exclude, &add_unique(&1, code))

    {:noreply,
     socket
     |> assign(form: form, exclude_query: "", exclude_results: [], exclude_open: false)
     |> reload_filters_async()}
  end

  def handle_event("exclude_category", %{"code" => code}, socket) do
    form = Map.update!(socket.assigns.form, :industries_exclude, &add_unique(&1, code))
    {:noreply, socket |> assign(form: form) |> reload_filters_async()}
  end

  def handle_event("confirm", _params, socket) do
    socket = assign(socket, confirming?: true)
    campaign = socket.assigns.campaign
    filters = filter_args(socket.assigns.form, campaign.market)

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
             |> put_flash(:info, gettext("Filters updated — top-up scheduled."))}

          # Fresh campaign + no active plan → starting work needs a plan, so
          # send them to pricing rather than into the target step.
          not Colt.Accounts.User.paid?(socket.assigns.current_user) ->
            {:noreply, push_navigate(socket, to: ~p"/pricing")}

          true ->
            {:noreply, push_navigate(socket, to: ~p"/campaigns/#{campaign.id}/target")}
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
    args = filter_args(socket.assigns.form, socket.assigns.campaign.market)

    case Filters.run(args) do
      {:ok, summary} ->
        assign(socket,
          count: summary.count,
          total: summary.total,
          preview: summary.preview,
          bucket_totals: summary.bucket_totals,
          top_industries: summary.top_industries,
          last_sync: summary.last_sync,
          pending?: false,
          reload_ref: nil
        )

      {:error, err} ->
        assign(socket, error: inspect(err), pending?: false, reload_ref: nil)
    end
  end

  defp default_form(campaign) do
    saved = campaign.filters || %{}

    %{
      industries: Map.get(saved, "industries", []),
      industries_exclude: Map.get(saved, "industries_exclude", []),
      growth_buckets: Map.get(saved, "growth_buckets", []),
      employees_min: Map.get(saved, "employees_min"),
      employees_max: Map.get(saved, "employees_max"),
      revenue_min: Map.get(saved, "revenue_min"),
      revenue_max: Map.get(saved, "revenue_max")
    }
  end

  defp filter_args(form, market) do
    %{
      market: market,
      industries: form.industries,
      industries_exclude: form.industries_exclude,
      growth_buckets: form.growth_buckets,
      employees_min: form.employees_min,
      employees_max: form.employees_max,
      revenue_min: form.revenue_min,
      revenue_max: form.revenue_max
    }
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

  defp toggle_in_form(form, "industries", v), do: Map.update!(form, :industries, &toggle(&1, v))

  defp toggle_in_form(form, "industries_exclude", v),
    do: Map.update!(form, :industries_exclude, &toggle(&1, v))

  defp toggle_in_form(form, "growth_buckets", v) do
    Map.update!(form, :growth_buckets, &toggle(&1, String.to_existing_atom(v)))
  end

  defp remove_from_form(form, "industries", v),
    do: Map.update!(form, :industries, &List.delete(&1, v))

  defp remove_from_form(form, "industries_exclude", v),
    do: Map.update!(form, :industries_exclude, &List.delete(&1, v))

  defp remove_from_form(form, "growth_buckets", v) do
    Map.update!(form, :growth_buckets, &List.delete(&1, String.to_existing_atom(v)))
  end

  defp toggle(list, value) do
    if value in list, do: List.delete(list, value), else: [value | list]
  end

  defp add_unique(list, value) do
    if value in list, do: list, else: [value | list]
  end

  defp parse_int(nil), do: nil
  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case String.replace(s, ~r/[^0-9]/, "") do
      "" -> nil
      digits -> String.to_integer(digits)
    end
  end

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
      <div class="flex flex-col lg:flex-row gap-6 lg:gap-12 flex-1 min-h-0">
        <.filter_panel
          form={@form}
          top_industries={@top_industries}
          bucket_totals={@bucket_totals}
          industry_query={@industry_query}
          industry_results={@industry_results}
          industry_open={@industry_open}
          exclude_query={@exclude_query}
          exclude_results={@exclude_results}
          exclude_open={@exclude_open}
        />

        <div class="flex-1 flex flex-col min-h-0 gap-5">
          <.counter_card count={@count} total={@total} pending?={@pending?} />

          <div class="flex items-center gap-4">
            <.link
              navigate={~p"/campaigns/#{@campaign.id}/market"}
              class="inline-flex items-center gap-2 px-3 py-[7px] text-[12px] border border-ink20 rounded-sharp no-underline text-ink"
            >
              <Liid.icon name="chev-l" size={11} /> {gettext("Back")}
            </.link>
            <Liid.btn
              variant={:primary}
              mono
              phx-click="confirm"
              disabled={@confirming? or @count == 0}
            >
              {confirm_label(@campaign.status)}
            </Liid.btn>
            <span :if={@error} class="font-mono text-[11px] text-fail">{@error}</span>
          </div>

          <.active_chips form={@form} />

          <.preview_list preview={@preview} count={@count} pending?={@pending?} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :form, :map, required: true
  attr :top_industries, :list, required: true
  attr :bucket_totals, :map, required: true
  attr :industry_query, :string, required: true
  attr :industry_results, :list, required: true
  attr :industry_open, :boolean, required: true
  attr :exclude_query, :string, required: true
  attr :exclude_results, :list, required: true
  attr :exclude_open, :boolean, required: true

  defp filter_panel(assigns) do
    assigns = assign(assigns, growth_buckets: @growth_buckets)

    ~H"""
    <div class="lg:basis-[360px] lg:shrink-0 flex flex-col min-h-0 gap-7">
      <Liid.headline kicker={gettext("04 / Filters")}>
        {raw(gettext("Narrow the <em>funnel</em>."))}
      </Liid.headline>

      <div class="flex flex-col gap-6 overflow-auto pr-2">
        <.fset label={gettext("Industry")} hint={industry_hint(@form.industries)}>
          <.industry_box
            mode={:include}
            selected={@form.industries}
            top_industries={@top_industries}
            query={@industry_query}
            results={@industry_results}
            open={@industry_open}
          />
        </.fset>

        <.fset label={gettext("Exclude industries")} hint={industry_hint(@form.industries_exclude)}>
          <.industry_box
            mode={:exclude}
            selected={@form.industries_exclude}
            top_industries={@top_industries}
            query={@exclude_query}
            results={@exclude_results}
            open={@exclude_open}
          />
        </.fset>

        <.range_fset
          label={gettext("Employees")}
          field="employees"
          min={@form.employees_min}
          max={@form.employees_max}
          format={:int}
        />

        <.range_fset
          label={gettext("Revenue (€)")}
          field="revenue"
          min={@form.revenue_min}
          max={@form.revenue_max}
          format={:money}
        />

        <.fset
          label={gettext("Trajectory")}
          hint={gettext("%{n} selected", n: length(@form.growth_buckets))}
        >
          <div class="flex flex-col gap-1">
            <%= for bucket <- @growth_buckets do %>
              <% on = bucket in @form.growth_buckets %>
              <% label = growth_label(bucket) %>
              <button
                type="button"
                phx-click="toggle"
                phx-value-field="growth_buckets"
                phx-value-v={bucket}
                class={[
                  "flex items-center gap-2.5 px-2.5 py-2 cursor-pointer text-left border-l-2",
                  on && "border-l-[var(--accent)]",
                  not on && "border-l-transparent"
                ]}
                style={on && "background: color-mix(in oklch, var(--accent) 7%, transparent);"}
              >
                <.checkbox checked={on} />
                <span class="text-[13px] text-ink flex-1">{label}</span>
                <span class="font-mono text-[11px] text-ink40 tnum">
                  {Map.get(@bucket_totals, bucket, 0)}
                </span>
              </button>
            <% end %>
          </div>
          <div class="font-mono text-[11px] text-ink40 mt-2 tracking-[0.04em]">
            {gettext("growth = revenue Δ over 3 fiscal years")}
          </div>
        </.fset>
      </div>
    </div>
    """
  end

  attr :mode, :atom, default: :include, values: [:include, :exclude]
  attr :selected, :list, required: true
  attr :top_industries, :list, required: true
  attr :query, :string, required: true
  attr :results, :list, required: true
  attr :open, :boolean, required: true

  defp industry_box(assigns) do
    items = if assigns.query == "", do: assigns.top_industries, else: assigns.results
    label = if assigns.query == "", do: gettext("popular"), else: gettext("matches")

    {field, search_evt, pick_evt, open_evt, close_evt, placeholder} =
      case assigns.mode do
        :include ->
          {"industries", "industry_search", "industry_pick", "industry_open", "industry_close",
           gettext("search industries…")}

        :exclude ->
          {"industries_exclude", "exclude_search", "exclude_pick", "exclude_open",
           "exclude_close", gettext("search to exclude…")}
      end

    assigns =
      assign(assigns,
        items: items,
        items_label: label,
        field: field,
        search_evt: search_evt,
        pick_evt: pick_evt,
        open_evt: open_evt,
        close_evt: close_evt,
        placeholder: placeholder
      )

    ~H"""
    <div class="relative" phx-click-away={@close_evt}>
      <div class="flex flex-wrap items-center gap-1.5 min-h-[36px] px-2 py-1.5 border border-ink20 bg-paperAlt rounded-sharp focus-within:border-ink">
        <%= for code <- @selected do %>
          <span class="inline-flex items-center gap-1.5 pl-2 pr-1 py-0.5 text-[11px] bg-paper border border-ink20 rounded-sharp">
            {industry_label(code)}
            <button
              type="button"
              phx-click="clear_chip"
              phx-value-field={@field}
              phx-value-v={code}
              class="text-ink55 hover:text-ink cursor-pointer"
            >
              <Liid.icon name="x" size={9} />
            </button>
          </span>
        <% end %>
        <form phx-change={@search_evt} autocomplete="off" class="flex-1 min-w-[80px]">
          <input
            type="text"
            name="q"
            value={@query}
            placeholder={if @selected == [], do: @placeholder, else: gettext("+ add")}
            phx-focus={@open_evt}
            phx-debounce="150"
            class="w-full bg-transparent text-[12px] text-ink outline-none placeholder:text-ink40"
          />
        </form>
      </div>

      <div
        :if={@open}
        class="absolute z-10 left-0 right-0 top-full mt-1 bg-paper border border-ink20 rounded-sharp shadow-[0_8px_24px_-12px_rgba(0,0,0,0.25)] max-h-[280px] overflow-auto"
      >
        <div class="px-3 py-1.5 font-mono text-[10px] tracking-[0.12em] uppercase text-ink40 border-b border-rule">
          {@items_label}
        </div>
        <div :if={@items == []} class="px-3 py-2.5 font-mono text-[11px] text-ink40">
          {gettext("no matches")}
        </div>
        <%= for item <- @items do %>
          <% {code, right} = item %>
          <% disabled = code in @selected %>
          <button
            type="button"
            phx-click={not disabled && @pick_evt}
            phx-value-code={code}
            disabled={disabled}
            class={[
              "w-full text-left px-3 py-2 flex items-baseline gap-2 border-b border-rule last:border-b-0",
              disabled && "opacity-40 cursor-not-allowed",
              not disabled && "hover:bg-paperAlt cursor-pointer"
            ]}
          >
            <span class="font-mono text-[10px] text-ink40 tnum w-9 shrink-0">{code}</span>
            <span class="text-[12px] text-ink truncate flex-1">{industry_label(code)}</span>
            <span :if={is_integer(right)} class="font-mono text-[10px] text-ink40 tnum">
              {right}
            </span>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp industry_hint([]), do: nil
  defp industry_hint(list), do: gettext("%{n} selected", n: length(list))

  attr :label, :string, required: true
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
    <.fset label={@label} hint={range_hint(@min, @max, @cap, @format)}>
      <form phx-change="update_slider" class="space-y-3">
        <input type="hidden" name="field" value={@field} />

        <div class="relative h-5">
          <div class="absolute left-0 right-0 top-1/2 -translate-y-1/2 h-px bg-ink20" />
          <div
            class="absolute top-1/2 -translate-y-1/2 h-[3px]"
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

      <form phx-change="update_range" class="flex gap-2 mt-2">
        <input type="hidden" name="field" value={@field} />
        <input
          type="text"
          inputmode="numeric"
          name="min"
          value={format_grouped(@min)}
          placeholder={gettext("min")}
          phx-debounce="600"
          class="flex-1 px-2.5 py-1.5 border border-ink20 bg-paperAlt font-mono text-[12px] rounded-sharp outline-none focus:border-ink"
        />
        <span class="self-center text-ink40">—</span>
        <input
          type="text"
          inputmode="numeric"
          name="max"
          value={format_grouped(@max)}
          placeholder={gettext("max")}
          phx-debounce="600"
          class="flex-1 px-2.5 py-1.5 border border-ink20 bg-paperAlt font-mono text-[12px] rounded-sharp outline-none focus:border-ink"
        />
      </form>
    </.fset>
    """
  end

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

  attr :checked, :boolean, required: true

  defp checkbox(assigns) do
    ~H"""
    <span
      class={[
        "w-3 h-3 border flex items-center justify-center rounded-[2px]",
        @checked && "border-[var(--accent)]",
        not @checked && "border-ink40"
      ]}
      style={@checked && "background: var(--accent);"}
    >
      <Liid.icon :if={@checked} name="check" size={9} class="text-paper" />
    </span>
    """
  end

  attr :label, :string, required: true
  attr :hint, :string, default: nil
  slot :inner_block, required: true

  defp fset(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-baseline mb-2.5 pb-2 border-b border-rule">
        <span class="font-mono text-[11px] tracking-[0.08em] uppercase text-ink70">
          {@label}
        </span>
        <span :if={@hint} class="font-mono text-[10px] text-ink40">{@hint}</span>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :count, :integer, required: true
  attr :total, :integer, required: true
  attr :pending?, :boolean, default: false

  defp counter_card(assigns) do
    ~H"""
    <div class="border border-ink20 bg-paperAlt rounded-sharp p-5 md:p-7 relative">
      <div>
        <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-2 flex items-center gap-2">
          {gettext("Companies match")}
          <span
            :if={@pending?}
            class="w-1.5 h-1.5 rounded-full animate-[liid-pulse_1.4s_ease-in-out_infinite]"
            style="background: var(--accent);"
          />
        </div>
        <div class="flex items-baseline gap-3">
          <div class={[
            "font-serif text-[56px] md:text-[76px] font-normal leading-[0.9] tnum tracking-[-0.02em] transition-opacity",
            @pending? && "opacity-40",
            not @pending? && "text-ink"
          ]}>
            {format_int(@count)}
          </div>
          <div class="font-mono text-[12px] text-ink55 pb-2">
            {gettext("of %{n}", n: format_int(@total))}
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp confirm_label(:enriching), do: gettext("Save filters")
  defp confirm_label(_), do: gettext("Continue → Target")

  attr :form, :map, required: true

  defp active_chips(assigns) do
    chips = active_chip_list(assigns.form)
    assigns = assign(assigns, chips: chips)

    ~H"""
    <div :if={@chips != []} class="flex flex-wrap gap-1.5 items-center">
      <span class="font-mono text-[10px] text-ink40 tracking-[0.12em] uppercase mr-1">
        {gettext("active")}
      </span>
      <%= for {field, value, label} <- @chips do %>
        <button
          type="button"
          phx-click="clear_chip"
          phx-value-field={field}
          phx-value-v={value}
          class="inline-flex items-center gap-1.5 px-2 py-1 text-[11px] bg-paperAlt border border-ink20 rounded-sharp cursor-pointer"
        >
          {label}
          <Liid.icon name="x" size={9} class="text-ink55" />
        </button>
      <% end %>
    </div>
    """
  end

  defp active_chip_list(form) do
    Enum.map(form.growth_buckets, fn b ->
      {"growth_buckets", to_string(b), gettext("Trajectory · %{label}", label: growth_label(b))}
    end)
  end

  attr :preview, :list, required: true
  attr :count, :integer, required: true
  attr :pending?, :boolean, default: false

  defp preview_list(assigns) do
    ~H"""
    <div class="flex-1 min-h-0 flex flex-col border border-rule rounded-sharp relative">
      <div class="px-4 py-3 border-b border-rule flex items-center justify-between font-mono text-[11px] tracking-[0.04em] text-ink55">
        <span class="flex items-center gap-2">
          <span
            :if={@pending?}
            class="w-1.5 h-1.5 rounded-full animate-[liid-pulse_1.4s_ease-in-out_infinite]"
            style="background: var(--accent);"
          /> {gettext("preview")} {if @pending?, do: gettext("· refreshing"), else: gettext("· live")}
        </span>
        <span>
          {gettext("showing %{shown} of %{total}", shown: length(@preview), total: format_int(@count))}
        </span>
      </div>
      <div class="flex-1 overflow-auto">
        <%= for c <- @preview do %>
          <div class="group grid grid-cols-[1fr_60px_50px] sm:grid-cols-[minmax(0,0.85fr)_minmax(0,1.4fr)_72px_52px] items-center gap-3 sm:gap-4 px-4 py-2.5 border-b border-rule text-[13px]">
            <div class="min-w-0">
              <div class="text-ink font-medium truncate">{c.name}</div>
              <div class="text-ink55 text-[11px] truncate sm:hidden">
                {industry_label(c.industry_code)}
              </div>
            </div>
            <span class="hidden sm:flex items-center gap-1.5 min-w-0 text-ink55 text-[12px]">
              <span class="truncate">{industry_label(c.industry_code)}</span>
              <button
                :if={c.industry_code}
                type="button"
                phx-click="exclude_category"
                phx-value-code={c.industry_code}
                title={gettext("Exclude this category")}
                aria-label={gettext("Exclude this category")}
                class="shrink-0 text-ink40 hover:text-fail cursor-pointer opacity-0 group-hover:opacity-100 focus:opacity-100 transition-opacity"
              >
                <Liid.icon name="x" size={10} />
              </button>
            </span>
            <span class="font-mono text-[11px] text-ink55 text-right tnum">
              {c.employees_latest || "—"}
            </span>
            <span class="font-mono text-[11px] text-right">
              {growth_glyph(c.revenue_growth_bucket)}
            </span>
          </div>
        <% end %>
      </div>
      <div
        class="absolute bottom-0 left-0 right-0 h-12 pointer-events-none"
        style="background: linear-gradient(180deg, transparent, var(--paper));"
      />
    </div>
    """
  end

  defp growth_glyph(:growing_10x), do: "10×"
  defp growth_glyph(:growing_2x), do: "2×"
  defp growth_glyph(:slow), do: "↗"
  defp growth_glyph(:stagnant), do: "→"
  defp growth_glyph(:declining), do: "↘"
  defp growth_glyph(_), do: "—"

  defp growth_label(:growing_10x), do: gettext("Growing · 10×")
  defp growth_label(:growing_2x), do: gettext("Growing · 2×")
  defp growth_label(:slow), do: gettext("Growing · slow")
  defp growth_label(:stagnant), do: gettext("Stagnant")
  defp growth_label(:declining), do: gettext("Shrinking")
  defp growth_label(_), do: "—"

  defp industry_label(nil), do: "—"

  defp industry_label(code) do
    Colt.Filters.IndustryLabels.label(code) || code
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
end
