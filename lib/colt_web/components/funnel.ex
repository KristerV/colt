defmodule ColtWeb.Components.Funnel do
  @moduledoc """
  View 4 building blocks: StatsStrip, MetaStrip, FunnelRow, EnrichmentPills,
  ExpandedDetail.

  Visual source of truth: `priv/design_prototype/project/view-4.jsx`.
  """
  use Phoenix.Component

  alias ColtWeb.Components.Liid

  @stage_labels %{
    website: "Website",
    icp: "ICP fit",
    contact: "Contact"
  }

  @stage_keys ~w(website icp contact)a

  def stage_keys, do: @stage_keys
  def stage_labels, do: @stage_labels

  attr :stats, :map, required: true
  attr :total, :integer, required: true
  attr :selected, :atom, default: :enriched

  def stats_strip(assigns) do
    tiles = [
      %{key: :queued, label: "Queued", color: "var(--ink40)", pulse?: false},
      %{key: :working, label: "Working", color: "var(--accent)", pulse?: true},
      %{key: :enriched, label: "Enriched", color: "var(--accent)", pulse?: false},
      %{key: :rejected, label: "ICP miss", color: "var(--ink40)", pulse?: false},
      %{key: :failed, label: "Failed", color: "var(--fail)", pulse?: false}
    ]

    assigns = assign(assigns, tiles: tiles)

    ~H"""
    <div class="flex overflow-x-auto md:overflow-visible border border-rule rounded-sharp">
      <%= for {tile, i} <- Enum.with_index(@tiles) do %>
        <% n = Map.get(@stats, tile.key, 0) %>
        <% pct = if @total > 0, do: n / @total * 100, else: 0 %>
        <% active? = @selected == tile.key %>
        <button
          type="button"
          phx-click="select_bucket"
          phx-value-bucket={tile.key}
          class={[
            "shrink-0 md:shrink min-w-[120px] md:min-w-0 md:flex-1 px-[14px] py-[12px] md:px-[18px] md:py-[14px] relative text-left cursor-pointer bg-transparent",
            i < length(@tiles) - 1 && "border-r border-rule",
            active? && "bg-paperAlt"
          ]}
          style={active? && "box-shadow: inset 0 -2px 0 var(--accent);"}
        >
          <div class="flex items-center justify-between mb-1.5">
            <span class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 flex items-center gap-1.5">
              <span
                :if={tile.pulse? and n > 0}
                class="w-[5px] h-[5px] rounded-full animate-[liid-pulse_1.4s_ease-in-out_infinite]"
                style={"background: #{tile.color};"}
              />
              {tile.label}
            </span>
            <span class="font-mono text-[10px] text-ink40">{Float.round(pct, 1)}%</span>
          </div>
          <div class="font-serif text-[36px] font-normal leading-none tracking-[-0.02em] text-ink tnum">
            {n}
          </div>
          <div class="mt-3 h-[2px] bg-ink10 relative">
            <div
              class="absolute left-0 top-0 bottom-0"
              style={"width: #{min(pct * 2, 100)}%; background: #{tile.color};"}
            />
          </div>
        </button>
      <% end %>
    </div>
    """
  end

  attr :meta, :map, required: true
  attr :visible, :integer, required: true
  attr :total, :integer, required: true

  def meta_strip(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-4 gap-y-1.5 md:gap-6 font-mono text-[11px] text-ink55 tracking-[0.04em] py-2">
      <span class="flex items-center gap-2">
        <span
          class="w-1.5 h-1.5 rounded-full animate-[liid-pulse_1.4s_ease-in-out_infinite]"
          style="background: var(--accent);"
        /> running · {@meta.workers} workers · {@meta.rate}/s
      </span>
      <span>queue: {@meta.queue}</span>
      <span>elapsed: {fmt_hms(@meta.elapsed_s)}</span>
      <span>eta: {fmt_hms(@meta.eta_s)}</span>
      <span class="ml-auto">{@visible} of {@total} visible</span>
    </div>
    """
  end

  def funnel_header(assigns) do
    ~H"""
    <div
      class="hidden md:grid items-center gap-3 px-4 border-b border-rule bg-paperAlt"
      style="grid-template-columns: 24px 1.5fr 70px 60px 1.6fr 1.2fr 1.2fr 1fr;"
    >
      <span class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 py-[11px]">
        <span class="inline-block w-3 h-3 border border-ink40 rounded-[2px]" />
      </span>
      <span class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 py-[11px]">
        Company
      </span>
      <span class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 py-[11px] text-right">
        Size
      </span>
      <span class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 py-[11px] text-center">
        Growth
      </span>
      <span class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 py-[11px]">
        Enrichment
      </span>
      <span class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 py-[11px]">
        Contact
      </span>
      <span class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 py-[11px]">
        Email / Phone
      </span>
      <span class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 py-[11px] text-right">
        Status
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :expanded?, :boolean, default: false
  attr :log, :list, default: []
  attr :admin?, :boolean, default: false

  def funnel_row(assigns) do
    ~H"""
    <div
      class="md:border-b md:border-rule mx-3 my-2 md:mx-0 md:my-0 border border-rule rounded-sharp md:border-x-0 md:border-t-0 md:rounded-none bg-paper"
      id={@id}
    >
      <div
        class={[
          "hidden md:grid items-center gap-3 px-4 py-3 cursor-pointer",
          @row.status == :scraping && "bg-[color-mix(in_oklch,var(--accent)_4%,transparent)]",
          @expanded? && "bg-paperAlt"
        ]}
        style="grid-template-columns: 24px 1.5fr 70px 60px 1.6fr 1.2fr 1.2fr 1fr;"
        phx-click="toggle_row"
        phx-value-id={@row.cc_id}
      >
        <span class="inline-block w-3 h-3 border border-ink40 rounded-[2px]" />
        <div class="min-w-0">
          <div class="text-[13px] text-ink font-medium truncate">{@row.name}</div>
          <div class="font-mono text-[10px] text-ink40 mt-0.5 tracking-[0.04em] truncate">
            <%= if @row.domain do %>
              {@row.domain}
            <% else %>
              <span class="italic">resolving...</span>
            <% end %>
            · {@row.registry_code}
          </div>
        </div>
        <span class="font-mono text-[11px] text-ink55 text-right tnum">
          {fmt_int(@row.size)}
        </span>
        <span class="flex justify-center">
          <.growth_glyph bucket={@row.growth} />
        </span>
        <.enrichment_pills stages={@row.stages} />
        <.contact_cell row={@row} />
        <.contact_meta_cell row={@row} />
        <.status_cell status={@row.status} failed_stage={Map.get(@row, :failed_stage)} />
      </div>

      <div
        class={[
          "md:hidden flex flex-col gap-2.5 px-4 py-3 cursor-pointer",
          @row.status == :scraping && "bg-[color-mix(in_oklch,var(--accent)_4%,transparent)]",
          @expanded? && "bg-paperAlt"
        ]}
        phx-click="toggle_row"
        phx-value-id={@row.cc_id}
      >
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0 flex-1">
            <div class="text-[14px] text-ink font-medium truncate">{@row.name}</div>
            <div class="font-mono text-[10px] text-ink40 mt-0.5 tracking-[0.04em] truncate">
              <%= if @row.domain do %>
                {@row.domain}
              <% else %>
                <span class="italic">resolving...</span>
              <% end %>
              · {@row.registry_code}
            </div>
          </div>
          <.status_cell status={@row.status} failed_stage={Map.get(@row, :failed_stage)} />
        </div>

        <div class="flex items-center justify-between gap-3 flex-wrap">
          <.enrichment_pills stages={@row.stages} />
          <div class="flex items-center gap-3 font-mono text-[10px] text-ink55 tracking-[0.04em]">
            <span class="flex items-center gap-1">
              <span class="text-ink40 uppercase">size</span>
              <span class="tnum">{fmt_int(@row.size)}</span>
            </span>
            <span class="flex items-center gap-1">
              <span class="text-ink40 uppercase">growth</span>
              <.growth_glyph bucket={@row.growth} />
            </span>
          </div>
        </div>

        <div :if={@row.status == :enriched and @row.contact} class="pt-2 mt-1 border-t border-rule">
          <div class="text-[12px] text-ink font-medium truncate">{@row.contact.name}</div>
          <div class="font-mono text-[10px] text-ink40 mt-0.5 truncate">
            {@row.contact.title || "—"}
          </div>
          <div :if={@row.contact.email} class="font-mono text-[10px] text-ink70 mt-1 truncate">
            {@row.contact.email}
          </div>
          <div :if={@row.contact.phone} class="font-mono text-[10px] text-ink70 mt-0.5 truncate tnum">
            {@row.contact.phone}
          </div>
        </div>
      </div>

      <.expanded_detail :if={@expanded?} row={@row} log={@log} admin?={@admin?} />
    </div>
    """
  end

  attr :stages, :map, required: true

  def enrichment_pills(assigns) do
    assigns = assign(assigns, keys: @stage_keys, labels: @stage_labels)

    ~H"""
    <div class="flex items-center gap-1.5">
      <%= for {key, i} <- Enum.with_index(@keys) do %>
        <% st = Map.get(@stages, key, :idle) %>
        <span
          class="inline-flex items-center gap-1 px-1.5 py-[3px] font-mono text-[10px] tracking-[0.04em] rounded-[2px] border"
          style={pill_style(st)}
        >
          <.pill_dot state={st} />
          {Map.fetch!(@labels, key)}
        </span>
        <span :if={i < 2} class="w-1 h-px bg-ink20" />
      <% end %>
    </div>
    """
  end

  attr :state, :atom, required: true

  defp pill_dot(assigns) do
    ~H"""
    <%= case @state do %>
      <% :work -> %>
        <span
          class="w-[6px] h-[6px] rounded-full animate-[liid-pulse_1.4s_ease-in-out_infinite]"
          style="background: var(--ink);"
        />
      <% :done -> %>
        <span class="w-[6px] h-[6px] rounded-full" style="background: var(--accent);" />
      <% :fail -> %>
        <span class="w-[6px] h-[6px] rounded-full" style="background: var(--fail);" />
      <% :fall -> %>
        <span class="w-[6px] h-[6px] rounded-full" style="background: var(--warn);" />
      <% :skip -> %>
        <span class="w-[6px] h-[6px] rounded-full" style="background: var(--ink40);" />
      <% _ -> %>
        <span class="w-[6px] h-[6px] rounded-full border" style="border-color: var(--ink20);" />
    <% end %>
    """
  end

  attr :row, :map, required: true

  def contact_cell(assigns) do
    ~H"""
    <%= cond do %>
      <% @row.status == :enriched and @row.contact -> %>
        <div class="min-w-0">
          <div class="text-[12px] text-ink font-medium truncate">{@row.contact.name}</div>
          <div class="font-mono text-[10px] text-ink40 mt-0.5 truncate">
            {@row.contact.title || "—"}
          </div>
        </div>
      <% @row.status == :enriched -> %>
        <span class="font-mono text-[11px] text-fail">no contact</span>
      <% @row.status == :rejected -> %>
        <span class="font-mono text-[11px] text-ink40">—</span>
      <% @row.status in [:no_website, :no_contacts, :failed] -> %>
        <span class="font-mono text-[11px] text-ink40">—</span>
      <% true -> %>
        <span
          class="inline-block h-2 w-[70%] bg-ink10 rounded-[1px]"
          style="background-image: linear-gradient(90deg, transparent, var(--ink20), transparent); background-size: 200% 100%; animation: liid-shimmer 1.6s ease-in-out infinite;"
        />
    <% end %>
    """
  end

  attr :row, :map, required: true

  def contact_meta_cell(assigns) do
    ~H"""
    <%= cond do %>
      <% @row.status == :enriched and @row.contact -> %>
        <div class="min-w-0 flex flex-col gap-0.5 font-mono text-[10px]">
          <span :if={@row.contact.email} class="text-ink70 truncate">{@row.contact.email}</span>
          <span :if={@row.contact.phone} class="text-ink70 truncate tnum">{@row.contact.phone}</span>
          <span :if={!@row.contact.email and !@row.contact.phone} class="text-ink40">—</span>
        </div>
      <% true -> %>
        <span class="font-mono text-[11px] text-ink40">—</span>
    <% end %>
    """
  end

  attr :status, :atom, required: true
  attr :failed_stage, :atom, default: nil

  def status_cell(assigns) do
    {label, color, pulse?} = status_view(assigns.status, assigns.failed_stage)
    assigns = assign(assigns, label: label, color: color, pulse?: pulse?)

    ~H"""
    <div
      class="flex items-center gap-2 justify-end font-mono text-[11px] tracking-[0.04em]"
      style={"color: #{@color};"}
    >
      <span
        class={[
          "w-1.5 h-1.5 rounded-full",
          @pulse? && "animate-[liid-pulse_1.4s_ease-in-out_infinite]"
        ]}
        style={"background: #{@color};"}
      /> {@label}
    </div>
    """
  end

  attr :bucket, :atom, default: nil

  def growth_glyph(assigns) do
    {heights, color} = growth_style(assigns.bucket)
    assigns = assign(assigns, heights: heights, color: color)

    ~H"""
    <span class="flex items-end gap-[1.5px] h-3">
      <%= for h <- @heights do %>
        <span
          class="w-[3px]"
          style={"height: #{h}px; background: #{@color}; opacity: 0.85;"}
        />
      <% end %>
    </span>
    """
  end

  attr :row, :map, required: true
  attr :log, :list, default: []
  attr :admin?, :boolean, default: false

  def expanded_detail(assigns) do
    ~H"""
    <div class="grid gap-6 md:gap-8 bg-paperAlt border-t border-rule grid-cols-1 md:grid-cols-[1.4fr_1fr] px-4 py-5 md:pl-14 md:pr-6 md:py-6">
      <div class="md:col-span-2 flex justify-end gap-2 -mb-2">
        <button
          :if={@row.status == :enriched}
          type="button"
          phx-click="open_not_a_fit"
          phx-value-id={@row.cc_id}
          class="inline-flex items-center gap-1.5 px-2.5 py-1 font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 border border-ink20 rounded-sharp hover:text-ink hover:border-ink40 cursor-pointer"
        >
          <Liid.icon name="x" size={11} /> Not a good fit
        </button>
        <button
          :if={@admin?}
          type="button"
          phx-click="retry_row"
          phx-value-id={@row.cc_id}
          data-confirm="Delete all enrichment data for this company and start over?"
          class="inline-flex items-center gap-1.5 px-2.5 py-1 font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 border border-ink20 rounded-sharp hover:text-ink hover:border-ink40 cursor-pointer"
        >
          <Liid.icon name="refresh" size={11} /> Retry (admin)
        </button>
      </div>
      <div class="flex flex-col gap-6">
        <div :if={@row.summary}>
          <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-3">
            Company summary
          </div>
          <div class="text-[12px] text-ink70 leading-[1.6]">
            {@row.summary}
          </div>
        </div>

        <div :if={Map.get(@row, :website_url)}>
          <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-2">
            Website
          </div>
          <a
            href={@row.website_url}
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1.5 text-[12px] text-ink hover:text-[var(--accent)] underline decoration-ink20 underline-offset-2"
          >
            <Liid.icon name="link" size={11} class="text-ink55" />
            {@row.domain || @row.website_url}
          </a>
        </div>

        <div :if={Map.get(@row, :scraped_paths, []) != []}>
          <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-2">
            Scraped pages ({length(@row.scraped_paths)})
          </div>
          <div class="font-mono text-[11px] leading-[1.7] text-ink70 flex flex-col">
            <a
              :for={p <- @row.scraped_paths}
              href={"#{@row.website_url}#{p}"}
              target="_blank"
              rel="noopener"
              class="text-ink hover:text-[var(--accent)] truncate"
            >
              {p}
            </a>
          </div>
          <div class="text-[10px] text-ink40 mt-2 leading-[1.5]">
            All pages above were combined into one input for the contact-extraction LLM call.
          </div>
        </div>

        <div>
          <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-3">
            Pipeline
          </div>
          <div class="font-mono text-[11px] leading-[1.7] text-ink70">
            <%= if @log == [] do %>
              <span class="text-ink40">no pipeline events yet</span>
            <% else %>
              <%= for entry <- @log do %>
                <div class="grid gap-2" style="grid-template-columns: 70px 14px 1fr;">
                  <span class="text-ink40">{entry.t}</span>
                  <span class={(entry.ok? && "text-[var(--accent)]") || "text-fail"}>
                    {entry.symbol}
                  </span>
                  <span class="break-words whitespace-pre-wrap">{entry.msg}</span>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>

      <div>
        <%= if @row.status in [:rejected, :no_website, :no_contacts, :failed] do %>
          <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-3">
            Outcome
          </div>
          <div class="px-5 py-[18px] bg-paper border border-ink20 rounded-sharp">
            <div
              class="font-mono text-[11px] tracking-[0.04em] uppercase mb-2"
              style="color: var(--fail);"
            >
              {outcome_label(@row.status, Map.get(@row, :failed_stage))}
            </div>
            <div :if={@row.rejection_reason} class="text-[12px] text-ink70 leading-[1.5]">
              {@row.rejection_reason}
            </div>
            <div :if={!@row.rejection_reason} class="text-[12px] text-ink40 italic">
              no reason recorded
            </div>

            <details
              :if={@admin? and Map.get(@row, :failure_detail)}
              class="mt-3 pt-3 border-t border-rule"
            >
              <summary class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 cursor-pointer">
                Technical detail (admin)
              </summary>
              <pre class="mt-2 text-[11px] text-ink70 leading-[1.5] whitespace-pre-wrap break-all max-h-64 overflow-auto bg-paperAlt p-3 rounded-sharp"><%= @row.failure_detail %></pre>
            </details>
          </div>
        <% else %>
          <div class="flex items-baseline justify-between mb-3">
            <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55">
              Extracted contact
            </div>
            <div :if={Map.get(@row, :total_contacts, 0) > 0} class="font-mono text-[10px] text-ink40">
              {@row.total_contacts} total
            </div>
          </div>
          <%= if @row.contact do %>
            <div class="px-5 py-[18px] bg-paper border border-ink20 rounded-sharp">
              <div class="font-serif text-[24px] tracking-[-0.02em] mb-1">
                {@row.contact.name}
              </div>
              <div class="text-[13px] text-ink55 mb-4">
                {@row.contact.title || "—"} · {@row.name}
              </div>
              <div class="flex flex-col gap-2 font-mono text-[11px]">
                <div :if={@row.contact.email} class="flex items-center gap-2">
                  <Liid.icon name="mail" size={11} class="text-ink55" />
                  <span class="text-ink">{@row.contact.email}</span>
                  <span class="ml-auto text-[10px]" style="color: var(--accent);">verified</span>
                </div>
                <div :if={@row.contact.phone} class="flex items-center gap-2">
                  <Liid.icon name="phone" size={11} class="text-ink55" />
                  <span class="text-ink tnum">{@row.contact.phone}</span>
                </div>
                <a
                  :if={Map.get(@row, :website_url)}
                  href={@row.website_url}
                  target="_blank"
                  rel="noopener"
                  class="flex items-center gap-2 hover:text-[var(--accent)]"
                >
                  <Liid.icon name="link" size={11} class="text-ink55" />
                  <span class="text-ink truncate">{@row.domain || @row.website_url}</span>
                </a>
              </div>
            </div>

            <div :if={Map.get(@row, :extra_contacts, []) != []} class="mt-4">
              <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-2">
                Other contacts
              </div>
              <div class="flex flex-col gap-2">
                <div
                  :for={ec <- @row.extra_contacts}
                  class="px-3 py-2 bg-paper border border-ink20 rounded-sharp"
                >
                  <div class="text-[12px] text-ink font-medium truncate">{ec.name}</div>
                  <div class="text-[11px] text-ink55 mb-1 truncate">{ec.title || "—"}</div>
                  <div :if={ec.email} class="font-mono text-[10px] text-ink70 truncate">
                    {ec.email}
                  </div>
                  <div :if={ec.phone} class="font-mono text-[10px] text-ink70 truncate tnum">
                    {ec.phone}
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <div class="text-[12px] text-ink40 italic">no contact extracted</div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp outcome_label(:rejected, _), do: "icp miss"
  defp outcome_label(:no_website, _), do: "no website"
  defp outcome_label(:no_contacts, _), do: "no contacts"
  defp outcome_label(:failed, :website), do: "website failed"
  defp outcome_label(:failed, :icp), do: "icp failed"
  defp outcome_label(:failed, :contact), do: "contact failed"
  defp outcome_label(:failed, _), do: "failed"
  defp outcome_label(_, _), do: ""

  defp pill_style(:idle),
    do: "border-color: var(--ink20); color: var(--ink40); opacity: 0.55;"

  # Working stage: black border + ink fill, dot pulses (the dot animation
  # comes from <.status_dot state={:work}>). Distinct from done's green tint.
  defp pill_style(:work),
    do: "border-color: var(--ink); color: var(--ink); background: transparent;"

  defp pill_style(:done),
    do:
      "border-color: var(--ink20); color: var(--ink); background: color-mix(in oklch, var(--accent) 14%, transparent);"

  defp pill_style(:skip),
    do: "border-color: var(--ink20); color: var(--ink40);"

  defp pill_style(:fall),
    do:
      "border-color: var(--warn); color: var(--warn); background: color-mix(in oklch, var(--warn) 10%, transparent);"

  defp pill_style(:fail),
    do:
      "border-color: var(--fail); color: var(--fail); background: color-mix(in oklch, var(--fail) 10%, transparent);"

  defp status_view(:pending, _), do: {"queued", "var(--ink40)", false}
  defp status_view(:scraping, _), do: {"working", "var(--ink)", true}
  defp status_view(:enriched, _), do: {"enriched", "var(--accent)", false}
  defp status_view(:rejected, _), do: {"icp miss", "var(--ink40)", false}
  defp status_view(:no_website, _), do: {"no website", "var(--warn)", false}
  defp status_view(:no_contacts, _), do: {"no contacts", "var(--warn)", false}
  defp status_view(:failed, :website), do: {"website failed", "var(--fail)", false}
  defp status_view(:failed, :icp), do: {"icp failed", "var(--fail)", false}
  defp status_view(:failed, :contact), do: {"contact failed", "var(--fail)", false}
  defp status_view(:failed, _), do: {"failed", "var(--fail)", false}
  defp status_view(_, _), do: {"queued", "var(--ink40)", false}

  defp growth_style(:declining), do: {[4, 3, 2, 1], "var(--warn)"}
  defp growth_style(:stagnant), do: {[3, 3, 3, 3], "var(--ink40)"}
  defp growth_style(:slow), do: {[2, 3, 4, 5], "var(--ink70)"}
  defp growth_style(:growing_2x), do: {[2, 4, 6, 8], "var(--accent)"}
  defp growth_style(:growing_10x), do: {[2, 5, 8, 11], "var(--accent)"}
  defp growth_style(_), do: {[1, 1, 1, 1], "var(--ink20)"}

  defp fmt_int(nil), do: "—"

  defp fmt_int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.codepoints()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  defp fmt_hms(nil), do: "—"

  defp fmt_hms(s) when is_integer(s) and s >= 0 do
    h = div(s, 3600)
    m = div(rem(s, 3600), 60)
    sec = rem(s, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, sec]) |> IO.iodata_to_binary()
  end

  defp fmt_hms(_), do: "—"
end
