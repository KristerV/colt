defmodule ColtWeb.Components.Funnel do
  @moduledoc """
  View 4 building blocks: StatsStrip, MetaStrip, FunnelRow, EnrichmentPills,
  ExpandedDetail.

  Visual source of truth: `priv/design_prototype/project/view-4.jsx`.
  """
  use Phoenix.Component
  use Gettext, backend: ColtWeb.Gettext

  alias Colt.Filters.IndustryLabels
  alias ColtWeb.Components.Liid

  @stage_labels %{
    website: "Website",
    icp: "ICP fit",
    contact: "Contact",
    verify: "Verify"
  }

  defp stage_label(:website), do: gettext("Website")
  defp stage_label(:icp), do: gettext("ICP fit")
  defp stage_label(:contact), do: gettext("Contact")
  defp stage_label(:verify), do: gettext("Verify")

  @stage_keys ~w(website icp contact verify)a

  def stage_keys, do: @stage_keys
  def stage_labels, do: @stage_labels

  attr :stats, :map, required: true
  attr :total, :integer, required: true
  attr :selected, :atom, default: nil
  attr :target, :integer, default: nil
  attr :campaign_id, :string, required: true

  def stats_strip(assigns) do
    enriched_label =
      if assigns.target,
        do: gettext("Enriched (target: %{n})", n: assigns.target),
        else: gettext("Enriched")

    tiles = [
      %{key: :queued, label: gettext("Queued"), color: "var(--ink40)", pulse?: false},
      %{key: :working, label: gettext("Working"), color: "var(--ink40)", pulse?: true},
      %{key: :enriched, label: enriched_label, color: "var(--green)", pulse?: false},
      %{key: :rejected, label: gettext("ICP miss"), color: "var(--amber)", pulse?: false},
      %{
        key: :excluded,
        label: gettext("Already contacted"),
        color: "var(--ink40)",
        pulse?: false
      },
      %{key: :failed, label: gettext("Failed"), color: "var(--red)", pulse?: false}
    ]

    assigns = assign(assigns, tiles: tiles)

    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-2.5">
      <%= for tile <- @tiles do %>
        <% n = Map.get(@stats, tile.key, 0) %>
        <% pct = if @total > 0, do: n / @total * 100, else: 0.0 %>
        <% active? = @selected == tile.key %>
        <.link
          patch={"/campaigns/#{@campaign_id}/funnel/#{tile.key}"}
          class={[
            "no-underline px-[13px] py-[12px] relative text-left cursor-pointer rounded-[11px] border transition-all",
            active? &&
              "bg-accentSoft border-accentRing [box-shadow:0_0_0_1px_var(--accentRing),var(--shadow-card)]",
            not active? &&
              "bg-card border-border [box-shadow:var(--shadow)] hover:border-borderStrong"
          ]}
        >
          <div class="flex items-center justify-between mb-1.5">
            <span class="text-[11px] tracking-[0.04em] uppercase font-semibold flex items-center gap-1.5 text-inkSoft">
              <span
                :if={tile.pulse? and n > 0}
                class="relative w-[6px] h-[6px] rounded-full"
                style={"background: #{tile.color};"}
              >
                <span
                  class="absolute inset-0 rounded-full animate-[pulse-halo_1.4s_ease-out_infinite]"
                  style={"background: #{tile.color};"}
                />
              </span>
              <span
                :if={not tile.pulse?}
                class="w-[6px] h-[6px] rounded-full"
                style={"background: #{tile.color};"}
              />
              {tile.label}
            </span>
            <span class="text-[10px] text-inkFaint tnum">{Float.round(pct, 1)}%</span>
          </div>
          <div
            class="text-[27px] font-bold leading-none tracking-[-0.02em] tnum"
            style={"color: #{if tile.color == "var(--ink40)", do: "var(--ink)", else: tile.color};"}
          >
            {n}
          </div>
        </.link>
      <% end %>
    </div>
    """
  end

  attr :meta, :map, required: true
  attr :visible, :integer, required: true
  attr :total, :integer, required: true

  def meta_strip(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-4 gap-y-1.5 md:gap-6 text-[11px] text-inkSoft bg-card border border-border rounded-[8px] [box-shadow:var(--shadow)] px-3.5 py-2">
      <span class="flex items-center gap-2">
        <span class="relative w-1.5 h-1.5 rounded-full" style="background: var(--green);">
          <span
            class="absolute inset-0 rounded-full animate-[pulse-halo_1.4s_ease-out_infinite]"
            style="background: var(--green);"
          />
        </span>
        {gettext("running · %{workers} workers · %{rate}/s",
          workers: @meta.workers,
          rate: @meta.rate
        )}
      </span>
      <span class="tnum">{gettext("queue: %{n}", n: @meta.queue)}</span>
      <span class="tnum">{gettext("elapsed: %{t}", t: fmt_hms(@meta.elapsed_s))}</span>
      <span class="tnum">{gettext("eta: %{t}", t: fmt_hms(@meta.eta_s))}</span>
      <span class="ml-auto tnum">
        {gettext("%{visible} of %{total} visible", visible: @visible, total: @total)}
      </span>
    </div>
    """
  end

  def funnel_header(assigns) do
    ~H"""
    <div
      class="hidden md:grid items-center gap-3 px-4 border-b border-border bg-bgSoft"
      style="grid-template-columns: 24px 1.5fr 1.6fr 1.2fr 1.2fr 1fr;"
    >
      <span class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold py-[11px]">
        <span class="inline-block w-3 h-3 border border-borderStrong rounded-[4px]" />
      </span>
      <span class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold py-[11px]">
        {gettext("Company")}
      </span>
      <span class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold py-[11px]">
        {gettext("Enrichment")}
      </span>
      <span class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold py-[11px]">
        {gettext("Contact")}
      </span>
      <span class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold py-[11px]">
        {gettext("Email / Phone")}
      </span>
      <span class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold py-[11px] text-right">
        {gettext("Status")}
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :expanded?, :boolean, default: false
  attr :admin?, :boolean, default: false

  def funnel_row(assigns) do
    ~H"""
    <div
      class="md:border-b md:border-border mx-3 my-2 md:mx-0 md:my-0 border border-border rounded-[11px] [box-shadow:var(--shadow)] md:[box-shadow:none] md:border-x-0 md:border-t-0 md:rounded-none bg-card"
      id={@id}
    >
      <div
        class={[
          "hidden md:grid items-center gap-3 px-4 py-3 cursor-pointer",
          @expanded? && "bg-bgSoft"
        ]}
        style="grid-template-columns: 24px 1.5fr 1.6fr 1.2fr 1.2fr 1fr;"
        phx-click="toggle_row"
        phx-value-id={@row.cc_id}
      >
        <span class="inline-block w-3 h-3 border border-borderStrong rounded-[4px]" />
        <div class="min-w-0">
          <div class="text-[13px] text-ink font-medium truncate">{@row.name}</div>
          <div class="text-[10px] text-inkFaint mt-0.5 truncate">
            <%= if @row.domain do %>
              {@row.domain}
            <% else %>
              <span class="italic">{gettext("resolving...")}</span>
            <% end %>
          </div>
        </div>
        <.enrichment_pills stages={@row.stages} />
        <.contact_cell row={@row} />
        <.contact_meta_cell row={@row} />
        <.status_cell status={@row.status} failed_stage={Map.get(@row, :failed_stage)} />
      </div>

      <div
        class={[
          "md:hidden flex flex-col gap-2.5 px-4 py-3 cursor-pointer rounded-[11px]",
          @expanded? && "bg-bgSoft"
        ]}
        phx-click="toggle_row"
        phx-value-id={@row.cc_id}
      >
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0 flex-1">
            <div class="text-[14px] text-ink font-medium truncate">{@row.name}</div>
            <div class="text-[10px] text-inkFaint mt-0.5 truncate">
              <%= if @row.domain do %>
                {@row.domain}
              <% else %>
                <span class="italic">{gettext("resolving...")}</span>
              <% end %>
            </div>
          </div>
          <.status_cell status={@row.status} failed_stage={Map.get(@row, :failed_stage)} />
        </div>

        <div class="flex items-center justify-between gap-3 flex-wrap">
          <.enrichment_pills stages={@row.stages} />
        </div>

        <div
          :if={@row.status == :enriched and @row.contact}
          class="pt-2.5 mt-1 border-t border-border"
        >
          <div class="text-[12px] text-ink font-medium truncate">{@row.contact.name}</div>
          <div class="text-[10px] text-inkFaint mt-0.5 truncate">
            {@row.contact.title || "—"}
          </div>
          <div :if={@row.contact.email} class="text-[10px] text-inkSoft mt-1 truncate">
            {@row.contact.email}
          </div>
          <div :if={@row.contact.phone} class="text-[10px] text-inkSoft mt-0.5 truncate tnum">
            {@row.contact.phone}
          </div>
        </div>
      </div>

      <.expanded_detail :if={@expanded?} row={@row} admin?={@admin?} />
    </div>
    """
  end

  attr :stages, :map, required: true

  def enrichment_pills(assigns) do
    assigns = assign(assigns, keys: @stage_keys)

    ~H"""
    <div class="flex items-center gap-1.5">
      <%= for {key, i} <- Enum.with_index(@keys) do %>
        <% st = Map.get(@stages, key, :idle) %>
        <span
          class="inline-flex items-center gap-1 px-1.5 py-[3px] text-[10px] tracking-[0.04em] font-medium rounded-[8px] border"
          style={pill_style(st)}
        >
          <.pill_dot state={st} />
          {stage_label(key)}
        </span>
        <span :if={i < 3} class="w-1 h-px bg-border" />
      <% end %>
    </div>
    """
  end

  attr :state, :atom, required: true

  defp pill_dot(assigns) do
    ~H"""
    <%= case @state do %>
      <% :work -> %>
        <span class="relative w-[6px] h-[6px] rounded-full" style="background: var(--green);">
          <span
            class="absolute inset-0 rounded-full animate-[pulse-halo_1.4s_ease-out_infinite]"
            style="background: var(--green);"
          />
        </span>
      <% :done -> %>
        <span class="w-[6px] h-[6px] rounded-full" style="background: var(--green);" />
      <% :fail -> %>
        <span class="w-[6px] h-[6px] rounded-full" style="background: var(--red);" />
      <% :fall -> %>
        <span class="w-[6px] h-[6px] rounded-full" style="background: var(--amber);" />
      <% :skip -> %>
        <span class="w-[6px] h-[6px] rounded-full" style="background: var(--ink40);" />
      <% _ -> %>
        <span class="w-[6px] h-[6px] rounded-full border" style="border-color: var(--borderStrong);" />
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
          <div class="text-[10px] text-inkFaint mt-0.5 truncate">
            {@row.contact.title || "—"}
          </div>
        </div>
      <% @row.status == :enriched -> %>
        <span class="text-[11px] text-red">{gettext("no contact")}</span>
      <% @row.status == :rejected -> %>
        <span class="text-[11px] text-inkFaint">—</span>
      <% @row.status in [:no_website, :no_contacts, :verify_failed, :failed] -> %>
        <span class="text-[11px] text-inkFaint">—</span>
      <% true -> %>
        <span
          class="inline-block h-2 w-[70%] bg-ink10 rounded-[4px]"
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
        <div class="min-w-0 flex flex-col gap-0.5 text-[10px]">
          <span :if={@row.contact.email} class="text-inkSoft truncate">{@row.contact.email}</span>
          <span :if={@row.contact.phone} class="text-inkSoft truncate tnum">
            {@row.contact.phone}
          </span>
          <span :if={!@row.contact.email and !@row.contact.phone} class="text-inkFaint">—</span>
        </div>
      <% true -> %>
        <span class="text-[11px] text-inkFaint">—</span>
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
      class="flex items-center gap-2 justify-end text-[11px] font-medium"
      style={"color: #{@color};"}
    >
      <span :if={@pulse?} class="relative w-1.5 h-1.5 rounded-full" style={"background: #{@color};"}>
        <span
          class="absolute inset-0 rounded-full animate-[pulse-halo_1.4s_ease-out_infinite]"
          style={"background: #{@color};"}
        />
      </span>
      <span :if={not @pulse?} class="w-1.5 h-1.5 rounded-full" style={"background: #{@color};"} />
      {@label}
    </div>
    """
  end

  attr :row, :map, required: true
  attr :admin?, :boolean, default: false

  def expanded_detail(assigns) do
    ~H"""
    <div class="grid gap-6 md:gap-8 bg-bgSoft border-t border-border grid-cols-1 md:grid-cols-[1.4fr_1fr] px-4 py-5 md:pl-14 md:pr-6 md:py-6">
      <div class="md:col-span-2 flex justify-end gap-2 -mb-2">
        <button
          :if={@row.status == :enriched}
          type="button"
          phx-click="open_learning"
          phx-value-id={@row.cc_id}
          phx-value-mode="exclude"
          class="inline-flex items-center gap-1.5 px-2.5 py-1 text-[10px] tracking-[0.08em] uppercase font-semibold text-inkSoft border border-border bg-card rounded-[8px] hover:text-ink hover:border-borderStrong cursor-pointer"
        >
          <Liid.icon name="x" size={11} /> {gettext("Not a good fit")}
        </button>
        <button
          :if={@row.status == :rejected}
          type="button"
          phx-click="open_learning"
          phx-value-id={@row.cc_id}
          phx-value-mode="include"
          class="inline-flex items-center gap-1.5 px-2.5 py-1 text-[10px] tracking-[0.08em] uppercase font-semibold text-inkSoft border border-border bg-card rounded-[8px] hover:text-ink hover:border-borderStrong cursor-pointer"
        >
          <Liid.icon name="check" size={11} /> {gettext("Actually a good fit")}
        </button>
        <button
          :if={@row.status in [:enriched, :rejected]}
          type="button"
          phx-click="recheck_icp_row"
          phx-value-id={@row.cc_id}
          data-confirm={gettext("Re-check ICP fit for this company?")}
          class="inline-flex items-center gap-1.5 px-2.5 py-1 text-[10px] tracking-[0.08em] uppercase font-semibold text-inkSoft border border-border bg-card rounded-[8px] hover:text-ink hover:border-borderStrong cursor-pointer"
        >
          <Liid.icon name="refresh" size={11} /> {gettext("Re-check ICP")}
        </button>
        <button
          :if={@admin?}
          type="button"
          phx-click="open_api_calls"
          phx-value-id={@row.cc_id}
          class="inline-flex items-center gap-1.5 px-2.5 py-1 text-[10px] tracking-[0.08em] uppercase font-semibold text-inkSoft border border-border bg-card rounded-[8px] hover:text-ink hover:border-borderStrong cursor-pointer"
        >
          <Liid.icon name="code" size={11} /> {gettext("LLM calls (admin)")}
        </button>
        <button
          :if={@admin?}
          type="button"
          phx-click="retry_row"
          phx-value-id={@row.cc_id}
          data-confirm={gettext("Delete all enrichment data for this company and start over?")}
          class="inline-flex items-center gap-1.5 px-2.5 py-1 text-[10px] tracking-[0.08em] uppercase font-semibold text-inkSoft border border-border bg-card rounded-[8px] hover:text-ink hover:border-borderStrong cursor-pointer"
        >
          <Liid.icon name="refresh" size={11} /> {gettext("Retry (admin)")}
        </button>
      </div>
      <div class="flex flex-col gap-6">
        <.company_facts row={@row} />

        <div :if={@row.summary}>
          <div class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold mb-3">
            {gettext("Company summary")}
          </div>
          <div class="text-[12px] text-inkSoft leading-[1.6]">
            {@row.summary}
          </div>
        </div>

        <div :if={Map.get(@row, :icp_reason)}>
          <div class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold mb-2">
            {gettext("ICP decision")} · {if @row.status == :rejected,
              do: gettext("rejected"),
              else: gettext("matched")}
          </div>
          <div class="text-[12px] text-inkSoft leading-[1.6]">
            {@row.icp_reason}
          </div>
        </div>

        <div :if={Map.get(@row, :website_url)}>
          <div class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold mb-2">
            {gettext("Website")}
          </div>
          <a
            href={@row.website_url}
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1.5 text-[12px] text-ink hover:text-accent underline decoration-border underline-offset-2"
          >
            <Liid.icon name="link" size={11} class="text-inkFaint" />
            {@row.domain || @row.website_url}
          </a>
        </div>

        <div :if={Map.get(@row, :scraped_paths, []) != []}>
          <div class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold mb-2">
            {gettext("Scraped pages (%{n})", n: length(@row.scraped_paths))}
          </div>
          <div class="text-[11px] leading-[1.7] text-inkSoft flex flex-col">
            <a
              :for={p <- @row.scraped_paths}
              href={"#{@row.website_url}#{p}"}
              target="_blank"
              rel="noopener"
              class="text-ink hover:text-accent truncate"
            >
              {p}
            </a>
          </div>
          <div class="text-[10px] text-inkFaint mt-2 leading-[1.5]">
            {gettext(
              "All pages above were combined into one input for the contact-extraction LLM call."
            )}
          </div>
        </div>
      </div>

      <div>
        <%= if @row.status in [:rejected, :no_website, :no_contacts, :verify_failed, :failed] do %>
          <div class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold mb-3">
            {gettext("Outcome")}
          </div>
          <div class="px-5 py-[18px] bg-card border border-border rounded-[11px] [box-shadow:var(--shadow)]">
            <div
              class="text-[11px] tracking-[0.04em] uppercase font-semibold mb-2"
              style="color: var(--red);"
            >
              {outcome_label(@row.status, Map.get(@row, :failed_stage))}
            </div>
            <div :if={@row.rejection_reason} class="text-[12px] text-inkSoft leading-[1.5]">
              {@row.rejection_reason}
            </div>
            <div :if={!@row.rejection_reason} class="text-[12px] text-inkFaint italic">
              {gettext("no reason recorded")}
            </div>

            <details
              :if={@admin? and Map.get(@row, :failure_detail)}
              class="mt-3 pt-3 border-t border-border"
            >
              <summary class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold cursor-pointer">
                {gettext("Technical detail (admin)")}
              </summary>
              <pre class="mt-2 text-[11px] text-inkSoft leading-[1.5] whitespace-pre-wrap break-all max-h-64 overflow-auto bg-paperAlt p-3 rounded-[8px]"><%= @row.failure_detail %></pre>
            </details>
          </div>
        <% else %>
          <div class="flex items-baseline justify-between mb-3">
            <div class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold">
              {gettext("Extracted contact")}
            </div>
            <div :if={Map.get(@row, :total_contacts, 0) > 0} class="text-[10px] text-inkFaint tnum">
              {gettext("%{n} total", n: @row.total_contacts)}
            </div>
          </div>
          <%= if @row.contact do %>
            <div class="px-5 py-[18px] bg-card border border-border rounded-[11px] [box-shadow:var(--shadow)]">
              <div class="text-[17px] font-bold tracking-[-0.01em] mb-1 text-ink">
                {@row.contact.name}
              </div>
              <div class="text-[13px] text-inkSoft mb-4">
                {@row.contact.title || "—"} · {@row.name}
              </div>
              <div class="flex flex-col gap-2 text-[11px]">
                <div :if={@row.contact.email} class="flex items-center gap-2">
                  <Liid.icon name="mail" size={11} class="text-inkFaint" />
                  <span class="text-ink">{@row.contact.email}</span>
                  <span class="ml-auto text-[10px] font-semibold" style="color: var(--green);">
                    {gettext("verified")}
                  </span>
                </div>
                <div :if={@row.contact.phone} class="flex items-center gap-2">
                  <Liid.icon name="phone" size={11} class="text-inkFaint" />
                  <span class="text-ink tnum">{@row.contact.phone}</span>
                </div>
                <a
                  :if={Map.get(@row, :website_url)}
                  href={@row.website_url}
                  target="_blank"
                  rel="noopener"
                  class="flex items-center gap-2 hover:text-accent"
                >
                  <Liid.icon name="link" size={11} class="text-inkFaint" />
                  <span class="text-ink truncate">{@row.domain || @row.website_url}</span>
                </a>
              </div>
            </div>

            <div :if={Map.get(@row, :extra_contacts, []) != []} class="mt-4">
              <div class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold mb-2">
                {gettext("Other contacts")}
              </div>
              <div class="flex flex-col gap-2">
                <div
                  :for={ec <- @row.extra_contacts}
                  class="px-3 py-2 bg-card border border-border rounded-[8px] [box-shadow:var(--shadow)]"
                >
                  <div class="text-[12px] text-ink font-medium truncate">{ec.name}</div>
                  <div class="text-[11px] text-inkSoft mb-1 truncate">{ec.title || "—"}</div>
                  <div :if={ec.email} class="text-[10px] text-inkSoft truncate">
                    {ec.email}
                  </div>
                  <div :if={ec.phone} class="text-[10px] text-inkSoft truncate tnum">
                    {ec.phone}
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <div class="text-[12px] text-inkFaint italic">{gettext("no contact extracted")}</div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # Registry numbers we already hold on the company — no extra query, every field
  # is carried on the row map by `FunnelLive.row_for/1`. Facts that are nil are
  # dropped individually; if none survive, the whole card is omitted.
  attr :row, :map, required: true

  defp company_facts(assigns) do
    assigns = assign(assigns, :facts, facts_for(assigns.row))

    ~H"""
    <div :if={@facts != []}>
      <div class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold mb-3">
        {gettext("Company facts")}
      </div>
      <div class="px-5 py-[18px] bg-card border border-border rounded-[11px] flex flex-col gap-2">
        <div
          :for={{label, value, link} <- @facts}
          class="flex items-baseline justify-between gap-4"
        >
          <span class="text-[11px] text-inkSoft shrink-0">{label}</span>
          <a
            :if={link}
            href={link}
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1.5 text-[12px] text-ink tnum hover:text-accent underline decoration-border underline-offset-2"
          >
            <Liid.icon name="link" size={11} class="text-inkFaint" />{value}
          </a>
          <span :if={!link} class="text-[12px] text-ink tnum text-right">{value}</span>
        </div>
      </div>
    </div>
    """
  end

  defp facts_for(row) do
    [
      {gettext("Turnover"), format_revenue(Map.get(row, :revenue)), nil},
      {gettext("Employees"), format_count(Map.get(row, :size)), nil},
      {gettext("Growth"), growth_label(Map.get(row, :growth)), nil},
      {gettext("Industry"), industry_label(Map.get(row, :industry_code)), nil},
      {gettext("Region"), Map.get(row, :region), nil},
      {gettext("Reg. code"), Map.get(row, :registry_code),
       registry_url(Map.get(row, :registry_link))}
    ]
    |> Enum.reject(fn {_label, value, _link} -> value in [nil, ""] end)
  end

  # `Colt.CompanyRegistry.link/1` returns %{label:, url:} (or nil), not a bare URL.
  defp registry_url(%{url: url}) when is_binary(url), do: url
  defp registry_url(_), do: nil

  defp format_revenue(nil), do: nil

  defp format_revenue(%Decimal{} = d),
    do: d |> Decimal.round(0) |> Decimal.to_integer() |> format_revenue()

  defp format_revenue(n) when is_integer(n) and n >= 1_000_000,
    do: "€#{format_decimal(n / 1_000_000, 1)}M"

  defp format_revenue(n) when is_integer(n) and n >= 1_000, do: "€#{div(n, 1_000)}k"
  defp format_revenue(n) when is_integer(n) and n >= 0, do: "€#{n}"
  defp format_revenue(_), do: nil

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

  defp format_count(n) when is_integer(n) and n >= 0, do: Integer.to_string(n)
  defp format_count(_), do: nil

  # nil is the normal case, not a gap: the growth rollup leaves the bucket unset
  # for companies under €100k revenue or with fewer than two filed years.
  defp growth_label(:growing_10x), do: gettext("Growing · 10×")
  defp growth_label(:growing_2x), do: gettext("Growing · 2×")
  defp growth_label(:slow), do: gettext("Growing · slow")
  defp growth_label(:stagnant), do: gettext("Stagnant")
  defp growth_label(:declining), do: gettext("Shrinking")
  defp growth_label(_), do: nil

  defp industry_label(code) when is_binary(code) and code != "" do
    case IndustryLabels.label(code) do
      nil -> code
      label -> "#{label} (#{code})"
    end
  end

  defp industry_label(_), do: nil

  defp outcome_label(:rejected, _), do: gettext("icp miss")
  defp outcome_label(:no_website, _), do: gettext("no website")
  defp outcome_label(:no_contacts, _), do: gettext("no contacts")
  defp outcome_label(:verify_failed, _), do: gettext("email unverified")
  defp outcome_label(:failed, :website), do: gettext("website failed")
  defp outcome_label(:failed, :icp), do: gettext("icp failed")
  defp outcome_label(:failed, :contact), do: gettext("contact failed")
  defp outcome_label(:failed, :verify), do: gettext("verify failed")
  defp outcome_label(:failed, _), do: gettext("failed")
  defp outcome_label(_, _), do: ""

  defp pill_style(:idle),
    do: "border-color: var(--border); color: var(--ink40); opacity: 0.7;"

  # Working stage: green tint, dot pulses (the dot animation comes from
  # <.pill_dot state={:work}>).
  defp pill_style(:work),
    do: "border-color: var(--green); color: var(--green); background: var(--greenSoft);"

  defp pill_style(:done),
    do: "border-color: #bfe6d2; color: var(--green); background: var(--greenSoft);"

  defp pill_style(:skip),
    do: "border-color: var(--border); color: var(--ink40);"

  defp pill_style(:fall),
    do: "border-color: var(--amber); color: var(--amber); background: var(--amberSoft);"

  defp pill_style(:fail),
    do: "border-color: var(--red); color: var(--red); background: var(--redSoft);"

  defp status_view(:pending, _), do: {gettext("queued"), "var(--ink40)", false}
  defp status_view(:scraping, _), do: {gettext("working"), "var(--ink40)", true}
  defp status_view(:enriched, _), do: {gettext("enriched"), "var(--green)", false}
  defp status_view(:rejected, _), do: {gettext("icp miss"), "var(--amber)", false}
  defp status_view(:no_website, _), do: {gettext("no website"), "var(--amber)", false}
  defp status_view(:no_contacts, _), do: {gettext("no contacts"), "var(--amber)", false}
  defp status_view(:verify_failed, _), do: {gettext("email unverified"), "var(--red)", false}
  defp status_view(:failed, :website), do: {gettext("website failed"), "var(--red)", false}
  defp status_view(:failed, :icp), do: {gettext("icp failed"), "var(--red)", false}
  defp status_view(:failed, :contact), do: {gettext("contact failed"), "var(--red)", false}
  defp status_view(:failed, :verify), do: {gettext("verify failed"), "var(--red)", false}
  defp status_view(:failed, _), do: {gettext("failed"), "var(--red)", false}
  defp status_view(_, _), do: {gettext("queued"), "var(--ink40)", false}

  defp fmt_hms(nil), do: "—"

  defp fmt_hms(s) when is_integer(s) and s >= 0 do
    h = div(s, 3600)
    m = div(rem(s, 3600), 60)
    sec = rem(s, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, sec]) |> IO.iodata_to_binary()
  end

  defp fmt_hms(_), do: "—"

  @doc """
  Shared "learning" dialog — captures the user's reason for an ICP
  include/exclude decision. Used by the enrichment funnel and by the
  writing page. The host LiveView handles `submit_learning`/`close_learning`.
  """
  attr :row, :map, required: true
  attr :mode, :atom, required: true
  attr :saving?, :boolean, default: false
  attr :error, :string, default: nil

  attr :note, :string,
    default: nil,
    doc: "Subtitle copy; falls back to the enrichment 're-check' wording when nil."

  def learning_modal(assigns) do
    assigns = assign_new(assigns, :note_text, fn -> assigns.note || default_learning_note() end)

    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
      style="background: rgba(20,18,14,0.45); backdrop-filter: blur(2px);"
    >
      <div
        class="bg-card border border-border rounded-[11px] w-full max-w-[560px] my-auto px-6 py-7 md:px-9 md:pt-8 md:pb-7"
        style="box-shadow: 0 24px 80px rgba(0,0,0,0.18);"
        phx-click-away="close_learning"
        phx-window-keydown="close_learning"
        phx-key="escape"
      >
        <div class="flex justify-between items-start gap-3 mb-5">
          <div class="min-w-0">
            <div class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold mb-1.5 truncate">
              {learning_eyebrow(@mode)} · {@row.name}
            </div>
            <h2 class="font-semibold text-[20px] md:text-[24px] leading-[1.15] tracking-[-0.02em] m-0 text-ink">
              {Phoenix.HTML.raw(learning_heading(@mode))}
            </h2>
            <div class="text-[12px] text-inkSoft mt-2 leading-[1.55]">
              {@note_text}
            </div>
          </div>
          <button
            type="button"
            class="w-6 h-6 flex items-center justify-center cursor-pointer"
            phx-click="close_learning"
          >
            <Liid.icon name="x" size={14} />
          </button>
        </div>

        <form phx-submit="submit_learning" class="flex flex-col gap-4">
          <textarea
            id="learning-reason"
            name="reason"
            autofocus
            phx-update="ignore"
            placeholder={learning_placeholder(@mode)}
            class="w-full min-h-[120px] px-[16px] py-3 border border-border bg-card text-[14px] leading-[1.55] text-ink rounded-[8px] outline-none resize-y focus:border-accentRing focus:[box-shadow:inset_0_0_0_1px_var(--accentRing)]"
          ></textarea>

          <div :if={@error} class="text-[11px] text-red">{@error}</div>

          <div class="flex items-center gap-3 justify-end">
            <Liid.btn size={:small} type="button" phx-click="close_learning">
              {gettext("Cancel")}
            </Liid.btn>

            <%= if @mode == :reject do %>
              <Liid.btn
                size={:small}
                type="submit"
                name="scope"
                value="company"
                disabled={@saving?}
              >
                {gettext("Wrong company")}
              </Liid.btn>
              <Liid.btn
                size={:small}
                variant={:primary}
                type="submit"
                name="scope"
                value="contact"
                disabled={@saving?}
              >
                {if @saving?, do: gettext("Saving…"), else: gettext("Wrong contact")}
              </Liid.btn>
            <% else %>
              <Liid.btn
                size={:small}
                variant={:primary}
                type="submit"
                disabled={@saving?}
              >
                {if @saving?, do: gettext("Saving…"), else: gettext("Save learning")}
              </Liid.btn>
            <% end %>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp default_learning_note do
    gettext(
      "Tell us in your own words. We'll save it as a rule and apply it next time you re-check ICP — no other companies move until you do."
    )
  end

  defp learning_eyebrow(:exclude), do: gettext("Not a good fit")
  defp learning_eyebrow(:include), do: gettext("Actually a good fit")
  defp learning_eyebrow(:reject), do: gettext("Not a good fit")

  defp learning_heading(:exclude), do: gettext("What makes this a <em>miss</em>?")
  defp learning_heading(:include), do: gettext("What makes this a <em>match</em>?")
  defp learning_heading(:reject), do: gettext("What's <em>wrong</em> here?")

  defp learning_placeholder(:exclude),
    do: gettext("e.g. They're a pure reseller — we sell to manufacturers, not distributors.")

  defp learning_placeholder(:include),
    do:
      gettext("e.g. They manufacture in-house — the site just emphasises their distribution arm.")

  defp learning_placeholder(:reject),
    do:
      gettext(
        "e.g. Wrong person — this is a purchasing manager, not sales. Or: wrong company — they're a pure reseller."
      )
end
