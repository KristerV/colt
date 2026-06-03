defmodule ColtWeb.Campaigns.FunnelLive do
  @moduledoc """
  View 4 — live funnel. Subscribes to `Colt.Services.Enrichment.Broadcast`,
  patches per-row state on `:stage` and `:row` messages, refreshes the meta
  strip every 4s.
  """
  use ColtWeb, :live_view

  alias Colt.Resources.{ApiCall, Campaign, CampaignCompany, IcpLearning}

  alias Colt.Services.Enrichment.{
    Broadcast,
    GenerateIcpLearning,
    RecheckIcp,
    Retry,
    Stats,
    SweepRecheckIcp
  }

  alias Colt.Services.Export.Csv, as: ExportCsv
  alias ColtWeb.Components.{ApiCallLog, Funnel, Liid}

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  @stage_keys ~w(website icp contact verify)a

  @tick_ms 4_000

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, %{status: s} = campaign} when s in [:draft, :collecting] ->
        {:ok, push_navigate(socket, to: ~p"/campaigns/#{campaign.id}/target")}

      {:ok, campaign} ->
        all_rows = load_rows(campaign)
        rows_index = Map.new(all_rows, &{&1.cc_id, &1})
        stats = compute_stats(all_rows)
        selected_bucket = :enriched
        rows = Enum.filter(all_rows, &(bucket(&1.status) == selected_bucket))

        if connected?(socket) do
          Broadcast.subscribe(campaign.id)
          Process.send_after(self(), :tick, @tick_ms)
        end

        socket =
          socket
          |> assign(
            page_title: gettext("Funnel — %{name}", name: campaign.name),
            campaign: campaign,
            rows_index: rows_index,
            expanded_id: nil,
            stats: stats,
            selected_bucket: selected_bucket,
            total: length(all_rows),
            meta: Stats.run(campaign.finalized_at),
            show_export?: false,
            export_preview: nil,
            export_count: 0,
            learning_row: nil,
            learning_mode: :exclude,
            learning_error: nil,
            learning_saving?: false,
            api_calls_row: nil,
            api_calls: [],
            api_call_expanded_id: nil
          )
          |> stream(:rows, rows)

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_info({:rows_added, cc_ids}, socket) do
    new_rows = load_rows_for_ids(cc_ids)

    rows_index =
      Enum.reduce(new_rows, socket.assigns.rows_index, fn r, acc ->
        Map.put(acc, r.cc_id, r)
      end)

    socket =
      Enum.reduce(new_rows, socket, fn r, s ->
        if bucket(r.status) == s.assigns.selected_bucket do
          stream_insert(s, :rows, r)
        else
          s
        end
      end)

    new_total = socket.assigns.total + length(new_rows)

    new_stats =
      Enum.reduce(new_rows, socket.assigns.stats, fn r, acc ->
        Map.update(acc, bucket(r.status), 1, &(&1 + 1))
      end)

    {:noreply, assign(socket, rows_index: rows_index, total: new_total, stats: new_stats)}
  end

  def handle_info({:stage, cc_id, stage, state}, socket) do
    case Map.get(socket.assigns.rows_index, cc_id) do
      nil ->
        {:noreply, socket}

      row ->
        # The pipeline is sequential, so "stage S is now <state>" fully implies
        # the rest: everything before S is done, everything after idle. Rebuild
        # the whole frontier (same model the reload path uses) rather than
        # poking one pill — this self-corrects stale pills left over from a
        # prior terminal state, e.g. when RecheckIcp reopens a failed row.
        new_row = %{row | stages: stage_frontier(stage_index(stage), state)}
        {:noreply, replace_row(socket, new_row)}
    end
  end

  def handle_info({:row, cc_id, patch}, socket) do
    case Map.get(socket.assigns.rows_index, cc_id) do
      nil ->
        {:noreply, socket}

      row ->
        new_row = apply_patch(row, patch)

        socket =
          socket
          |> replace_row(new_row)
          |> maybe_recompute_stats(row.status, new_row.status)

        {:noreply, socket}
    end
  end

  def handle_info({:save_learning, cc_id, mode, reason}, socket) do
    campaign = socket.assigns.campaign
    row = Map.get(socket.assigns.rows_index, cc_id)

    with %{} <- row,
         {:ok, cc} <- CampaignCompany.get(cc_id, authorize?: false, load: [:company]),
         summary <- cc.company.ai_summary || row.summary || "",
         {:ok, rule} <-
           GenerateIcpLearning.run(
             campaign.icp_description || "",
             summary,
             reason,
             mode,
             campaign_id: campaign.id,
             subject: {:campaign_company, cc_id}
           ),
         {:ok, _} <- IcpLearning.create(campaign.id, rule, mode, cc.company_id) do
      {:noreply, assign(socket, learning_row: nil, learning_saving?: false, learning_error: nil)}
    else
      nil ->
        {:noreply, assign(socket, learning_saving?: false)}

      {:error, _} ->
        {:noreply,
         assign(socket,
           learning_saving?: false,
           learning_error: gettext("Couldn't generate the learning. Try again.")
         )}
    end
  end

  def handle_info(:tick, socket) do
    if connected?(socket) do
      Process.send_after(self(), :tick, @tick_ms)
    end

    {:noreply,
     socket
     |> assign(meta: Stats.run(socket.assigns.campaign.finalized_at))
     |> assign(current_user: ColtWeb.UsageAssign.load_usage(socket.assigns.current_user))}
  end

  # Toggle expand/collapse. Streams don't re-render existing items when a
  # parent assign changes, so the expanded flag has to live *on the row* and
  # be pushed via stream_insert. Tracking @expanded_id lets us collapse the
  # previous row when opening a new one.
  def handle_event("select_bucket", %{"bucket" => bucket}, socket) do
    bucket_atom = String.to_existing_atom(bucket)
    rows = filtered_rows(socket.assigns.rows_index, bucket_atom)
    {:noreply, socket |> assign(selected_bucket: bucket_atom) |> stream(:rows, rows, reset: true)}
  end

  def handle_event("open_export", _params, socket) do
    {:ok, %{rows: rows, row_count: count}} = ExportCsv.run(socket.assigns.campaign)
    preview = Enum.take(rows, 2)
    {:noreply, assign(socket, show_export?: true, export_preview: preview, export_count: count)}
  end

  def handle_event("close_export", _params, socket) do
    {:noreply, assign(socket, show_export?: false)}
  end

  def handle_event("recheck_icp_row", %{"id" => id}, socket) do
    {:ok, _} = RecheckIcp.run(id)
    {:noreply, socket}
  end

  def handle_event("recheck_icp", _params, socket) do
    if work_in_flight?(socket.assigns.stats) do
      {:noreply, socket}
    else
      {:ok, _} = SweepRecheckIcp.run(socket.assigns.campaign.id)
      {:noreply, socket}
    end
  end

  def handle_event("open_learning", %{"id" => id} = params, socket) do
    mode = parse_mode(params["mode"])

    case Map.get(socket.assigns.rows_index, id) do
      nil ->
        {:noreply, socket}

      row ->
        {:noreply, assign(socket, learning_row: row, learning_mode: mode, learning_error: nil)}
    end
  end

  def handle_event("close_learning", _params, socket) do
    {:noreply, assign(socket, learning_row: nil, learning_error: nil, learning_saving?: false)}
  end

  def handle_event("submit_learning", %{"reason" => reason}, socket) do
    reason = String.trim(reason || "")
    row = socket.assigns.learning_row
    mode = socket.assigns.learning_mode

    cond do
      row == nil ->
        {:noreply, socket}

      reason == "" ->
        {:noreply,
         assign(socket, learning_error: gettext("Tell us why so we can learn the rule."))}

      true ->
        socket = assign(socket, learning_saving?: true, learning_error: nil)
        send(self(), {:save_learning, row.cc_id, mode, reason})
        {:noreply, socket}
    end
  end

  defp parse_mode("include"), do: :include
  defp parse_mode(_), do: :exclude

  def handle_event("toggle_row", %{"id" => id}, socket) do
    case socket.assigns.expanded_id do
      ^id ->
        {:noreply, socket |> collapse(id) |> assign(expanded_id: nil)}

      nil ->
        {:noreply, socket |> expand(id) |> assign(expanded_id: id)}

      prev ->
        {:noreply, socket |> collapse(prev) |> expand(id) |> assign(expanded_id: id)}
    end
  end

  def handle_event("open_api_calls", %{"id" => id}, socket) do
    if socket.assigns.current_user.is_admin do
      row = Map.get(socket.assigns.rows_index, id)
      calls = ApiCall.list_for_subject!(:campaign_company, id, authorize?: false)

      {:noreply, assign(socket, api_calls_row: row, api_calls: calls, api_call_expanded_id: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_api_calls", _params, socket) do
    {:noreply, assign(socket, api_calls_row: nil, api_calls: [], api_call_expanded_id: nil)}
  end

  def handle_event("toggle_api_call", %{"id" => id}, socket) do
    next = if socket.assigns.api_call_expanded_id == id, do: nil, else: id
    {:noreply, assign(socket, api_call_expanded_id: next)}
  end

  def handle_event("retry_row", %{"id" => id}, socket) do
    if socket.assigns.current_user.is_admin do
      {:ok, _} = Retry.run(id)

      row =
        socket.assigns.rows_index
        |> Map.fetch!(id)
        |> Map.merge(%{
          status: :pending,
          failed_stage: nil,
          rejection_reason: nil,
          failure_detail: nil,
          summary: nil,
          website_url: nil,
          domain: nil,
          contact: nil,
          extra_contacts: [],
          total_contacts: 0,
          scraped_paths: [],
          stages: stages_for(:pending, nil, 0)
        })

      socket =
        socket
        |> replace_row(row)
        |> maybe_recompute_stats(socket.assigns.rows_index[id].status, :pending)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp expand(socket, id), do: replace_row(socket, id, expanded?: true)
  defp collapse(socket, id), do: replace_row(socket, id, expanded?: false)

  defp replace_row(socket, %{} = row) do
    socket = assign(socket, rows_index: Map.put(socket.assigns.rows_index, row.cc_id, row))

    if bucket(row.status) == socket.assigns.selected_bucket do
      stream_insert(socket, :rows, row)
    else
      stream_delete(socket, :rows, row)
    end
  end

  defp filtered_rows(rows_index, bucket_atom) do
    rows_index
    |> Map.values()
    |> Enum.filter(&(bucket(&1.status) == bucket_atom))
  end

  defp replace_row(socket, id, fields) when is_binary(id) do
    row = Map.fetch!(socket.assigns.rows_index, id) |> Map.merge(Map.new(fields))
    replace_row(socket, row)
  end

  defp maybe_recompute_stats(socket, same, same), do: socket

  defp maybe_recompute_stats(socket, old_status, new_status) do
    stats = socket.assigns.stats
    bucket_old = bucket(old_status)
    bucket_new = bucket(new_status)

    stats =
      stats
      |> Map.update(bucket_old, 0, &max(&1 - 1, 0))
      |> Map.update(bucket_new, 0, &(&1 + 1))

    assign(socket, stats: stats)
  end

  defp apply_patch(row, patch) do
    new_row =
      Enum.reduce(patch, row, fn
        {:status, v}, acc -> %{acc | status: v}
        {"status", v}, acc -> %{acc | status: v}
        {:failed_stage, v}, acc -> %{acc | failed_stage: v}
        {:rejection_reason, v}, acc -> %{acc | rejection_reason: v}
        {:icp_reason, v}, acc -> Map.put(acc, :icp_reason, v)
        {:failure_detail, v}, acc -> Map.put(acc, :failure_detail, v)
        {:summary, v}, acc -> Map.put(acc, :summary, v)
        {:website_url, v}, acc -> %{acc | website_url: v, domain: domain_of(v)}
        {:contact_name, v}, acc -> patch_contact(acc, :name, v)
        {:contact_title, v}, acc -> patch_contact(acc, :title, v)
        {:contact_email, v}, acc -> patch_contact(acc, :email, v)
        {:contact_phone, v}, acc -> patch_contact(acc, :phone, v)
        _other, acc -> acc
      end)

    # When the row reaches a terminal status, re-derive `stages` so the pills
    # always match the outcome — guards against missed/out-of-order :stage
    # broadcasts (e.g. worker crashes before emitting :fail).
    if terminal?(new_row.status) and not terminal?(row.status) do
      %{new_row | stages: stages_for(new_row.status, new_row.failed_stage, 0)}
    else
      new_row
    end
  end

  defp terminal?(s),
    do: s in [:enriched, :rejected, :no_website, :no_contacts, :verify_failed, :failed]

  defp patch_contact(row, key, value) do
    contact = row.contact || %{name: nil, title: nil, email: nil, phone: nil}
    %{row | contact: Map.put(contact, key, value)}
  end

  defp load_rows(campaign) do
    {:ok, ccs} =
      CampaignCompany.list_for_campaign(campaign.id,
        actor: nil,
        authorize?: false,
        load: [company: [:persons, :pages]]
      )

    Enum.map(ccs, &row_for/1)
  end

  defp load_rows_for_ids([]), do: []

  defp load_rows_for_ids(cc_ids) do
    {:ok, ccs} =
      CampaignCompany.list_by_ids(cc_ids,
        authorize?: false,
        load: [company: [:persons, :pages]]
      )

    Enum.map(ccs, &row_for/1)
  end

  defp row_for(cc) do
    company = cc.company
    person = pick_person(company.persons, cc.picked_person_id)
    extras = others(company.persons, person)

    %{
      id: "row-#{cc.id}",
      cc_id: cc.id,
      name: company.name,
      domain: domain_of(company.website_url),
      website_url: company.website_url,
      registry_code: company.registry_code,
      size: company.employees_latest,
      growth: company.revenue_growth_bucket,
      status: cc.status,
      failed_stage: cc.failed_stage,
      stages: stages_for(cc.status, cc.failed_stage, scraping_progress(cc, company)),
      contact: contact_for(person),
      extra_contacts: Enum.map(extras, &contact_for/1) |> Enum.take(3),
      total_contacts: length(company.persons),
      scraped_paths: scraped_paths(company.pages),
      summary: company.ai_summary,
      rejection_reason: cc.rejection_reason,
      icp_reason: cc.icp_reason,
      failure_detail: cc.failure_detail,
      expanded?: false
    }
  end

  defp others(persons, picked) do
    case picked do
      nil -> persons
      %{id: pid} -> Enum.reject(persons, &(&1.id == pid))
    end
  end

  defp scraped_paths(pages) do
    pages
    |> Enum.filter(&is_binary(&1.markdown))
    |> Enum.map(& &1.path)
    |> Enum.sort()
  end

  defp pick_person(_persons, nil), do: nil
  defp pick_person(persons, picked_id), do: Enum.find(persons, &(&1.id == picked_id))

  defp contact_for(nil), do: nil

  defp contact_for(p),
    do: %{name: p.name, title: p.title, email: p.email, phone: p.phone}

  defp domain_of(nil), do: nil
  defp domain_of(""), do: nil

  defp domain_of(url) do
    case URI.parse(url) do
      %URI{host: h} when is_binary(h) -> String.replace_prefix(h, "www.", "")
      _ -> nil
    end
  end

  # Snapshot pills from the CC's own persisted state — no Oban job lookups.
  # Maps a status to its frontier stage; reused by mount, new rows, and the
  # terminal re-derivation in apply_patch.
  defp stages_for(status, failed_stage, scraping_progress) do
    case status do
      :scraping -> stage_frontier(scraping_progress, :work)
      :enriched -> stage_frontier(4, :done)
      :no_website -> stage_frontier(0, :fall)
      :rejected -> stage_frontier(1, :fall)
      :no_contacts -> stage_frontier(2, :fall)
      :verify_failed -> stage_frontier(3, :fail)
      :failed when failed_stage in @stage_keys -> stage_frontier(stage_index(failed_stage), :fail)
      _ -> stage_frontier(0, :idle)
    end
  end

  # The single source of truth for what the pills mean, shared by the snapshot
  # (reload) and live `:stage` paths. The stage at `index` takes `state`,
  # everything before it is :done, everything after :idle. Monotonic by
  # construction: a later stage can never look further along than an earlier one.
  defp stage_frontier(index, state) do
    @stage_keys
    |> Enum.with_index()
    |> Map.new(fn {key, i} ->
      cond do
        i < index -> {key, :done}
        i == index -> {key, state}
        true -> {key, :idle}
      end
    end)
  end

  defp stage_index(:website), do: 0
  defp stage_index(:icp), do: 1
  defp stage_index(:contact), do: 2
  defp stage_index(:verify), do: 3

  # How many stages a scraping row has durably completed, read off the CC's
  # own data (no shared Company fields that would bleed across campaigns).
  # ai_summary lives on Company, but it *is* the website stage's output, so a
  # cached summary correctly means website is done for this CC too.
  defp scraping_progress(cc, company) do
    cond do
      cc.picked_person_id -> 3
      cc.icp_reason -> 2
      company.ai_summary -> 1
      true -> 0
    end
  end

  defp compute_stats(rows) do
    Enum.reduce(
      rows,
      %{queued: 0, working: 0, enriched: 0, rejected: 0, failed: 0},
      fn r, acc -> Map.update!(acc, bucket(r.status), &(&1 + 1)) end
    )
  end

  defp bucket(:pending), do: :queued
  defp bucket(:scraping), do: :working
  defp bucket(:enriched), do: :enriched
  defp bucket(:rejected), do: :rejected
  defp bucket(:no_website), do: :failed
  defp bucket(:no_contacts), do: :failed
  defp bucket(:verify_failed), do: :failed
  defp bucket(:failed), do: :failed
  defp bucket(_), do: :queued

  defp work_in_flight?(%{queued: q, working: w}), do: q + w > 0
  defp work_in_flight?(_), do: false

  defp bucket_label(:queued), do: gettext("Queued")
  defp bucket_label(:working), do: gettext("Working")
  defp bucket_label(:enriched), do: gettext("Enriched")
  defp bucket_label(:rejected), do: gettext("ICP miss")
  defp bucket_label(:failed), do: gettext("Failed")
  defp bucket_label(_), do: ""

  defp empty_message(:queued), do: gettext("Nothing waiting in line.")
  defp empty_message(:working), do: gettext("No companies currently being processed.")

  defp empty_message(:enriched),
    do: gettext("Nothing has been fully enriched yet. Pick another bucket to watch progress.")

  defp empty_message(:rejected),
    do: gettext("No companies have been rejected on ICP fit yet.")

  defp empty_message(:failed), do: gettext("Nothing has failed. Enjoy it.")
  defp empty_message(_), do: ""

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      step={5}
      campaign={@campaign}
      campaign_name={@campaign.name}
      campaign_id={@campaign.id}
    >
      <div class="flex flex-col gap-[18px] flex-1 min-h-0">
        <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4 sm:gap-6">
          <div class="min-w-0">
            <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-1.5 truncate">
              {gettext("05 / Funnel · %{name}", name: @campaign.name)}
            </div>
            <h1 class="font-serif font-normal text-[32px] md:text-[44px] leading-none tracking-[-0.02em] m-0">
              {gettext("Enriching")}
              <span style="color: var(--accent);">{@total}</span> {gettext("companies.")}
            </h1>
          </div>
          <% busy = work_in_flight?(@stats) %>
          <div class="flex items-center gap-3">
            <Liid.btn
              size={:small}
              mono
              disabled={busy}
              phx-click="recheck_icp"
              data-confirm={gettext("Re-check ICP fit on all enriched and ICP-rejected companies?")}
            >
              <Liid.icon name="refresh" size={11} /> {gettext("Re-check ICP")}
            </Liid.btn>
            <Liid.btn
              size={:small}
              variant={:primary}
              mono
              disabled={busy or @stats.enriched == 0}
              phx-click="open_export"
            >
              <Liid.icon name="download" size={11} /> {gettext("Export")}
            </Liid.btn>
          </div>
        </div>

        <Funnel.stats_strip
          stats={@stats}
          total={@total}
          selected={@selected_bucket}
          target={@campaign.target_contact_count}
        />

        <Funnel.meta_strip meta={@meta} visible={@total} total={@total} />

        <div class="flex-1 min-h-0 flex flex-col md:border md:border-rule md:rounded-sharp -mx-4 md:mx-0">
          <Funnel.funnel_header />
          <% bucket_count = Map.get(@stats, @selected_bucket, 0) %>
          <div :if={bucket_count == 0} class="flex-1 flex items-center justify-center px-6 py-12">
            <div class="text-center">
              <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink40 mb-2">
                {bucket_label(@selected_bucket)}
              </div>
              <div class="text-[14px] text-ink55 max-w-[420px]">
                {empty_message(@selected_bucket)}
              </div>
            </div>
          </div>
          <div
            :if={bucket_count > 0}
            class="flex-1 overflow-auto"
            id="funnel-body"
            phx-update="stream"
          >
            <Funnel.funnel_row
              :for={{dom_id, row} <- @streams.rows}
              id={dom_id}
              row={row}
              expanded?={row.expanded?}
              admin?={@current_user.is_admin}
            />
          </div>
        </div>
      </div>

      <.export_modal
        :if={@show_export?}
        campaign={@campaign}
        count={@export_count}
        preview={@export_preview}
      />

      <.learning_modal
        :if={@learning_row}
        row={@learning_row}
        mode={@learning_mode}
        saving?={@learning_saving?}
        error={@learning_error}
      />

      <.api_calls_modal
        :if={@api_calls_row}
        row={@api_calls_row}
        calls={@api_calls}
        expanded_id={@api_call_expanded_id}
      />
    </Layouts.app>
    """
  end

  attr :campaign, :map, required: true
  attr :count, :integer, required: true
  attr :preview, :list, required: true

  defp export_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
      style="background: rgba(20,18,14,0.45); backdrop-filter: blur(2px);"
    >
      <div
        class="bg-paper border border-ink20 rounded-sharp w-full max-w-[640px] my-auto px-6 py-7 md:px-9 md:pt-8 md:pb-7"
        style="box-shadow: 0 24px 80px rgba(0,0,0,0.18);"
        phx-click-away="close_export"
        phx-window-keydown="close_export"
        phx-key="escape"
      >
        <div class="flex justify-between items-start gap-3 mb-6">
          <div class="min-w-0">
            <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-1.5 truncate">
              {gettext("Export · %{name}", name: @campaign.name)}
            </div>
            <h2 class="font-serif font-normal text-[24px] md:text-[32px] leading-[1.1] tracking-[-0.02em] m-0">
              {gettext("Take")} <span style="color: var(--accent);">{@count}</span>
              {if @count == 1,
                do: gettext("enriched contact somewhere."),
                else: gettext("enriched contacts somewhere.")}
            </h2>
          </div>
          <button
            type="button"
            class="w-6 h-6 flex items-center justify-center cursor-pointer"
            phx-click="close_export"
          >
            <Liid.icon name="x" size={14} />
          </button>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <.format_card
            name="CSV"
            desc={gettext("Flat sheet · companies + primary contact")}
            note={gettext("%{n} rows", n: @count)}
            enabled
          />
          <.format_card
            name="JSON"
            desc={gettext("Nested · companies → people → pages")}
            note={gettext("soon")}
          />
          <.format_card
            name="HubSpot"
            desc={gettext("Push directly · de-dupe by domain")}
            note={gettext("soon")}
          />
          <.format_card
            name="Pipedrive"
            desc={gettext("Push directly · org + person + deal")}
            note={gettext("soon")}
          />
          <.format_card name="Apollo" desc={gettext("Add to sequence")} note={gettext("soon")} />
          <.format_card name="Webhook" desc={gettext("POST to your URL")} note={gettext("soon")} />
        </div>

        <div
          class="mt-5 bg-paperAlt rounded-sharp font-mono text-[11px] text-ink55"
          style="padding: 14px 16px; line-height: 1.6;"
        >
          <div class="text-ink70 mb-1">
            {gettext("liid-%{slug}.csv · preview", slug: slug(@campaign.name))}
          </div>
          <div>email,first_name,last_name,company_name,website,title,snippet</div>
          <div :for={row <- @preview} class="truncate hidden sm:block">
            {preview_line(row)}
          </div>
          <div :for={row <- @preview} class="sm:hidden break-all">
            {preview_line(row)}
          </div>
          <div :if={@preview == []} class="text-ink40">
            {gettext("(no rows yet — preview will appear once a contact is verified)")}
          </div>
        </div>

        <div class="flex gap-3 mt-6">
          <Liid.btn size={:small} phx-click="close_export">{gettext("Cancel")}</Liid.btn>
          <span class="flex-1"></span>
          <.link
            href={~p"/campaigns/#{@campaign.id}/export.csv"}
            class={[
              "inline-flex items-center gap-2 border rounded-[2px] font-medium cursor-pointer transition-all",
              "px-[18px] py-[10px] text-[13px] font-mono tracking-[0.04em]",
              "bg-ink text-paper border-ink",
              @count == 0 && "opacity-50 pointer-events-none"
            ]}
          >
            <Liid.icon name="download" size={11} /> {gettext("Download CSV")}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :desc, :string, required: true
  attr :note, :string, required: true
  attr :enabled, :boolean, default: false

  defp format_card(assigns) do
    ~H"""
    <div
      class={[
        "rounded-sharp",
        @enabled && "border cursor-pointer",
        !@enabled && "border border-ink20 opacity-45 cursor-not-allowed"
      ]}
      style={
        if @enabled,
          do:
            "padding: 14px 16px; border-color: var(--accent); background: color-mix(in oklch, var(--accent) 5%, transparent);",
          else: "padding: 14px 16px;"
      }
    >
      <div class="flex justify-between items-baseline">
        <span class="text-[14px] font-semibold text-ink">{@name}</span>
        <span class="font-mono text-[10px] text-ink40">{@note}</span>
      </div>
      <div class="text-[12px] text-ink55 mt-1">{@desc}</div>
    </div>
    """
  end

  attr :row, :map, required: true
  attr :mode, :atom, required: true
  attr :saving?, :boolean, default: false
  attr :error, :string, default: nil

  defp learning_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
      style="background: rgba(20,18,14,0.45); backdrop-filter: blur(2px);"
    >
      <div
        class="bg-paper border border-ink20 rounded-sharp w-full max-w-[560px] my-auto px-6 py-7 md:px-9 md:pt-8 md:pb-7"
        style="box-shadow: 0 24px 80px rgba(0,0,0,0.18);"
        phx-click-away="close_learning"
        phx-window-keydown="close_learning"
        phx-key="escape"
      >
        <div class="flex justify-between items-start gap-3 mb-5">
          <div class="min-w-0">
            <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-1.5 truncate">
              {learning_eyebrow(@mode)} · {@row.name}
            </div>
            <h2 class="font-serif font-normal text-[22px] md:text-[28px] leading-[1.15] tracking-[-0.02em] m-0">
              {Phoenix.HTML.raw(learning_heading(@mode))}
            </h2>
            <div class="text-[12px] text-ink55 mt-2 leading-[1.55]">
              {gettext(
                "Tell us in your own words. We'll save it as a rule and apply it next time you re-check ICP — no other companies move until you do."
              )}
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
            name="reason"
            autofocus
            placeholder={learning_placeholder(@mode)}
            class="w-full min-h-[120px] px-[16px] py-3 border border-ink20 bg-paperAlt text-[14px] leading-[1.55] text-ink rounded-sharp outline-none resize-y focus:border-ink"
          ></textarea>

          <div :if={@error} class="font-mono text-[11px] text-fail">{@error}</div>

          <div class="flex items-center gap-3 justify-end">
            <Liid.btn size={:small} type="button" phx-click="close_learning">
              {gettext("Cancel")}
            </Liid.btn>
            <Liid.btn
              size={:small}
              variant={:primary}
              mono
              type="submit"
              disabled={@saving?}
            >
              {if @saving?, do: gettext("Saving…"), else: gettext("Save learning")}
            </Liid.btn>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp learning_eyebrow(:exclude), do: gettext("Not a good fit")
  defp learning_eyebrow(:include), do: gettext("Actually a good fit")

  defp learning_heading(:exclude), do: gettext("What makes this a <em>miss</em>?")
  defp learning_heading(:include), do: gettext("What makes this a <em>match</em>?")

  defp learning_placeholder(:exclude),
    do: gettext("e.g. They're a pure reseller — we sell to manufacturers, not distributors.")

  defp learning_placeholder(:include),
    do:
      gettext("e.g. They manufacture in-house — the site just emphasises their distribution arm.")

  attr :row, :map, required: true
  attr :calls, :list, required: true
  attr :expanded_id, :string, default: nil

  defp api_calls_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
      style="background: rgba(20,18,14,0.45); backdrop-filter: blur(2px);"
    >
      <div
        class="bg-paper border border-ink20 rounded-sharp w-full max-w-[920px] my-auto px-6 py-7 md:px-9 md:pt-8 md:pb-7"
        style="box-shadow: 0 24px 80px rgba(0,0,0,0.18);"
        phx-click-away="close_api_calls"
        phx-window-keydown="close_api_calls"
        phx-key="escape"
      >
        <div class="flex justify-between items-start gap-3 mb-5">
          <div class="min-w-0">
            <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-1.5 truncate">
              {gettext("LLM calls · %{name}", name: @row.name)}
            </div>
            <h2 class="font-serif font-normal text-[22px] md:text-[28px] leading-[1.15] tracking-[-0.02em] m-0">
              {gettext("%{n} recorded calls", n: length(@calls))}
            </h2>
          </div>
          <button
            type="button"
            class="w-6 h-6 flex items-center justify-center cursor-pointer"
            phx-click="close_api_calls"
          >
            <Liid.icon name="x" size={14} />
          </button>
        </div>

        <ApiCallLog.api_call_list calls={@calls} expanded_id={@expanded_id} />
      </div>
    </div>
    """
  end

  defp preview_line(row) do
    ~w(email first_name last_name company_name website title snippet)
    |> Enum.map_join(",", &Map.get(row, &1, ""))
    |> String.slice(0, 110)
  end

  defp slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
