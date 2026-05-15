defmodule ColtWeb.Campaigns.FunnelLive do
  @moduledoc """
  View 4 — live funnel. Subscribes to `Colt.Services.Enrichment.Broadcast`,
  patches per-row state on `:stage` and `:row` messages, refreshes the meta
  strip every 4s.
  """
  use ColtWeb, :live_view

  import Ecto.Query

  alias Colt.Resources.{ApiCall, Campaign, CampaignCompany, IcpLearning}
  alias Colt.Services.Enrichment.{Broadcast, GenerateIcpLearning, Retry, Stats, SweepRecheckIcp}
  alias Colt.Services.Export.Csv, as: ExportCsv
  alias ColtWeb.Components.{ApiCallLog, Funnel, Liid}

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  @stage_keys ~w(website icp contact)a

  @tick_ms 4_000

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
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
            page_title: "Funnel — #{campaign.name}",
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
            not_a_fit_row: nil,
            not_a_fit_error: nil,
            not_a_fit_saving?: false,
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

  def handle_info({:stage, cc_id, stage, state}, socket) do
    case Map.get(socket.assigns.rows_index, cc_id) do
      nil ->
        {:noreply, socket}

      row ->
        new_stages = Map.put(row.stages, stage, state)
        new_row = %{row | stages: new_stages}
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

  def handle_info({:save_not_a_fit, cc_id, reason}, socket) do
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
             campaign_id: campaign.id,
             subject: {:campaign_company, cc_id}
           ),
         {:ok, _} <- IcpLearning.create(campaign.id, rule, cc.company_id) do
      {:noreply,
       assign(socket, not_a_fit_row: nil, not_a_fit_saving?: false, not_a_fit_error: nil)}
    else
      nil ->
        {:noreply, assign(socket, not_a_fit_saving?: false)}

      {:error, _} ->
        {:noreply,
         assign(socket,
           not_a_fit_saving?: false,
           not_a_fit_error: "Couldn't generate the learning. Try again."
         )}
    end
  end

  def handle_info(:tick, socket) do
    if connected?(socket) do
      Process.send_after(self(), :tick, @tick_ms)
    end

    {:noreply, assign(socket, meta: Stats.run(socket.assigns.campaign.finalized_at))}
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

  def handle_event("recheck_icp", _params, socket) do
    if work_in_flight?(socket.assigns.stats) do
      {:noreply, socket}
    else
      {:ok, _} = SweepRecheckIcp.run(socket.assigns.campaign.id)
      {:noreply, socket}
    end
  end

  def handle_event("open_not_a_fit", %{"id" => id}, socket) do
    case Map.get(socket.assigns.rows_index, id) do
      nil -> {:noreply, socket}
      row -> {:noreply, assign(socket, not_a_fit_row: row, not_a_fit_error: nil)}
    end
  end

  def handle_event("close_not_a_fit", _params, socket) do
    {:noreply, assign(socket, not_a_fit_row: nil, not_a_fit_error: nil, not_a_fit_saving?: false)}
  end

  def handle_event("submit_not_a_fit", %{"reason" => reason}, socket) do
    reason = String.trim(reason || "")
    row = socket.assigns.not_a_fit_row

    cond do
      row == nil ->
        {:noreply, socket}

      reason == "" ->
        {:noreply, assign(socket, not_a_fit_error: "Tell us why so we can learn the rule.")}

      true ->
        socket = assign(socket, not_a_fit_saving?: true, not_a_fit_error: nil)
        send(self(), {:save_not_a_fit, row.cc_id, reason})
        {:noreply, socket}
    end
  end

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
          stages: idle_stages(),
          log: pipeline_log(id)
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

  defp expand(socket, id), do: replace_row(socket, id, expanded?: true, log: pipeline_log(id))
  defp collapse(socket, id), do: replace_row(socket, id, expanded?: false, log: [])

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
        _other, acc -> acc
      end)

    # When the row reaches a terminal status, re-derive `stages` so the pills
    # always match the outcome — guards against missed/out-of-order :stage
    # broadcasts (e.g. worker crashes before emitting :fail).
    if terminal?(new_row.status) and not terminal?(row.status) do
      %{new_row | stages: snapshot_stages(new_row.status, new_row.failed_stage)}
    else
      new_row
    end
  end

  defp terminal?(s),
    do: s in [:enriched, :rejected, :no_website, :no_contacts, :failed]

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

    completed = completed_stage_workers(Enum.map(ccs, & &1.id))
    Enum.map(ccs, &row_for(&1, Map.get(completed, &1.id, MapSet.new())))
  end

  # Map of cc_id → MapSet of stages whose terminal worker has completed.
  # Lets snapshot_stages paint the right pills on page reload for rows
  # still in :scraping (otherwise they'd all show gray idle).
  @stage_workers %{
    "Colt.Jobs.Enrichment.SummarizeCompany" => :website,
    "Colt.Jobs.Enrichment.MatchICP" => :icp,
    "Colt.Jobs.Enrichment.ExtractContacts" => :contact
  }

  defp completed_stage_workers([]), do: %{}

  defp completed_stage_workers(cc_ids) do
    cc_id_strs = Enum.map(cc_ids, &to_string/1)
    workers = Map.keys(@stage_workers)

    q =
      from j in Oban.Job,
        where: j.worker in ^workers,
        where: j.state == "completed",
        where: fragment("?->>'campaign_company_id' = ANY(?)", j.args, ^cc_id_strs),
        select: {fragment("(?->>'campaign_company_id')::uuid", j.args), j.worker}

    Colt.Repo.all(q)
    |> Enum.reduce(%{}, fn {cc_id, worker}, acc ->
      stage = Map.fetch!(@stage_workers, worker)
      Map.update(acc, cc_id, MapSet.new([stage]), &MapSet.put(&1, stage))
    end)
  end

  defp row_for(cc, completed_stages) do
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
      stages: snapshot_stages(cc.status, cc.failed_stage, completed_stages),
      contact: contact_for(person),
      extra_contacts: Enum.map(extras, &contact_for/1) |> Enum.take(3),
      total_contacts: length(company.persons),
      scraped_paths: scraped_paths(company.pages),
      summary: company.ai_summary,
      rejection_reason: cc.rejection_reason,
      icp_reason: cc.icp_reason,
      failure_detail: cc.failure_detail,
      expanded?: false,
      log: []
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

  # Mark every stage *before* the given one as :done, the stage itself as
  # `state`, and everything after as :idle. Used for terminal snapshots on
  # page reload so the user sees where the run stopped.
  defp stages_up_to(stage, state) do
    Enum.reduce(@stage_keys, {%{}, :before}, fn k, {acc, mode} ->
      {label, next_mode} =
        cond do
          k == stage -> {state, :after}
          mode == :before -> {:done, :before}
          true -> {:idle, :after}
        end

      {Map.put(acc, k, label), next_mode}
    end)
    |> elem(0)
  end

  defp snapshot_stages(status, failed_stage, completed \\ MapSet.new())

  defp snapshot_stages(:pending, _, _), do: idle_stages()

  # For in-flight rows, derive pills from which terminal-stage workers have
  # completed. The next stage after the last :done becomes :work (pulsing),
  # the rest stay idle.
  defp snapshot_stages(:scraping, _, completed),
    do: scraping_stages(completed)

  defp snapshot_stages(:no_website, _, _), do: stages_up_to(:website, :fall)
  defp snapshot_stages(:rejected, _, _), do: stages_up_to(:icp, :fall)
  defp snapshot_stages(:no_contacts, _, _), do: stages_up_to(:contact, :fall)

  defp snapshot_stages(:enriched, _, _),
    do: %{website: :done, icp: :done, contact: :done}

  defp snapshot_stages(:failed, stage, _) when stage in @stage_keys,
    do: stages_up_to(stage, :fail)

  defp snapshot_stages(:failed, _, _), do: idle_stages()
  defp snapshot_stages(_, _, _), do: idle_stages()

  defp scraping_stages(completed) do
    {map, _} =
      Enum.reduce(@stage_keys, {%{}, false}, fn key, {acc, work_marked?} ->
        cond do
          MapSet.member?(completed, key) ->
            {Map.put(acc, key, :done), work_marked?}

          not work_marked? ->
            {Map.put(acc, key, :work), true}

          true ->
            {Map.put(acc, key, :idle), work_marked?}
        end
      end)

    map
  end

  defp idle_stages, do: Map.new(@stage_keys, &{&1, :idle})

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
  defp bucket(:failed), do: :failed
  defp bucket(_), do: :queued

  defp work_in_flight?(%{queued: q, working: w}), do: q + w > 0
  defp work_in_flight?(_), do: false

  defp bucket_label(:queued), do: "Queued"
  defp bucket_label(:working), do: "Working"
  defp bucket_label(:enriched), do: "Enriched"
  defp bucket_label(:rejected), do: "ICP miss"
  defp bucket_label(:failed), do: "Failed"
  defp bucket_label(_), do: ""

  defp empty_message(:queued), do: "Nothing waiting in line."
  defp empty_message(:working), do: "No companies currently being processed."

  defp empty_message(:enriched),
    do: "Nothing has been fully enriched yet. Pick another bucket to watch progress."

  defp empty_message(:rejected),
    do: "No companies have been rejected on ICP fit yet."

  defp empty_message(:failed), do: "Nothing has failed. Enjoy it."
  defp empty_message(_), do: ""

  defp pipeline_log(cc_id) do
    q =
      from(j in Oban.Job,
        where: like(j.worker, "Colt.Jobs.Enrichment.%"),
        where: fragment("?->>'campaign_company_id' = ?", j.args, ^cc_id),
        order_by: [asc: coalesce(j.completed_at, j.attempted_at)]
      )

    Colt.Repo.all(q)
    |> Enum.map(&log_line/1)
  end

  defp log_line(%Oban.Job{worker: w, state: state, completed_at: ct, attempted_at: at} = j) do
    ts = ct || at
    label = w |> String.split(".") |> List.last()
    {symbol, ok?} = if state == "completed", do: {"✓", true}, else: {"·", false}

    msg =
      case state do
        "completed" -> "#{label} done"
        "executing" -> "#{label} running…"
        "discarded" -> "#{label} failed: #{first_error(j.errors)}"
        "retryable" -> "#{label} retrying"
        s -> "#{label} #{s}"
      end

    %{
      t: format_time(ts),
      symbol: symbol,
      ok?: ok?,
      msg: msg
    }
  end

  defp first_error([%{"error" => err} | _]) when is_binary(err), do: err
  defp first_error(_), do: ""

  defp format_time(nil), do: "--:--:--"

  defp format_time(%DateTime{} = ts) do
    Calendar.strftime(ts, "%H:%M:%S")
  end

  defp format_time(%NaiveDateTime{} = ts) do
    Calendar.strftime(ts, "%H:%M:%S")
  end

  defp format_time(_), do: "--:--:--"

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      step={4}
      campaign={@campaign}
      campaign_name={@campaign.name}
      campaign_id={@campaign.id}
    >
      <div class="flex flex-col gap-[18px] flex-1 min-h-0">
        <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4 sm:gap-6">
          <div class="min-w-0">
            <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-1.5 truncate">
              05 / Funnel · {@campaign.name}
            </div>
            <h1 class="font-serif font-normal text-[32px] md:text-[44px] leading-none tracking-[-0.02em] m-0">
              Enriching <span style="color: var(--accent);">{@total}</span> companies.
            </h1>
          </div>
          <% busy = work_in_flight?(@stats) %>
          <div class="flex items-center gap-3">
            <Liid.btn
              size={:small}
              mono
              disabled={busy}
              phx-click="recheck_icp"
              data-confirm="Re-check ICP fit on all enriched and ICP-rejected companies?"
            >
              <Liid.icon name="refresh" size={11} /> Re-check ICP
            </Liid.btn>
            <Liid.btn
              size={:small}
              variant={:primary}
              mono
              disabled={busy or @stats.enriched == 0}
              phx-click="open_export"
            >
              <Liid.icon name="download" size={11} /> Export
            </Liid.btn>
          </div>
        </div>

        <Funnel.stats_strip stats={@stats} total={@total} selected={@selected_bucket} />

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
              log={row.log}
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

      <.not_a_fit_modal
        :if={@not_a_fit_row}
        row={@not_a_fit_row}
        saving?={@not_a_fit_saving?}
        error={@not_a_fit_error}
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
      phx-click="close_export"
    >
      <div
        class="bg-paper border border-ink20 rounded-sharp w-full max-w-[640px] my-auto px-6 py-7 md:px-9 md:pt-8 md:pb-7"
        style="box-shadow: 0 24px 80px rgba(0,0,0,0.18);"
        phx-click-away="close_export"
        phx-window-keydown="close_export"
        phx-key="escape"
        onclick="event.stopPropagation()"
      >
        <div class="flex justify-between items-start gap-3 mb-6">
          <div class="min-w-0">
            <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-1.5 truncate">
              Export · {@campaign.name}
            </div>
            <h2 class="font-serif font-normal text-[24px] md:text-[32px] leading-[1.1] tracking-[-0.02em] m-0">
              Take <span style="color: var(--accent);">{@count}</span>
              enriched {if @count == 1, do: "contact", else: "contacts"} somewhere.
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
            desc="Flat sheet · companies + primary contact"
            note={"#{@count} rows"}
            enabled
          />
          <.format_card name="JSON" desc="Nested · companies → people → pages" note="soon" />
          <.format_card name="HubSpot" desc="Push directly · de-dupe by domain" note="soon" />
          <.format_card name="Pipedrive" desc="Push directly · org + person + deal" note="soon" />
          <.format_card name="Apollo" desc="Add to sequence" note="soon" />
          <.format_card name="Webhook" desc="POST to your URL" note="soon" />
        </div>

        <div
          class="mt-5 bg-paperAlt rounded-sharp font-mono text-[11px] text-ink55"
          style="padding: 14px 16px; line-height: 1.6;"
        >
          <div class="text-ink70 mb-1">
            liid-{slug(@campaign.name)}.csv · preview
          </div>
          <div>email,first_name,last_name,company_name,website,title,snippet</div>
          <div :for={row <- @preview} class="truncate hidden sm:block">
            {preview_line(row)}
          </div>
          <div :for={row <- @preview} class="sm:hidden break-all">
            {preview_line(row)}
          </div>
          <div :if={@preview == []} class="text-ink40">
            (no rows yet — preview will appear once a contact is verified)
          </div>
        </div>

        <div class="flex gap-3 mt-6">
          <Liid.btn size={:small} phx-click="close_export">Cancel</Liid.btn>
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
            <Liid.icon name="download" size={11} /> Download CSV
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
  attr :saving?, :boolean, default: false
  attr :error, :string, default: nil

  defp not_a_fit_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
      style="background: rgba(20,18,14,0.45); backdrop-filter: blur(2px);"
      phx-click="close_not_a_fit"
    >
      <div
        class="bg-paper border border-ink20 rounded-sharp w-full max-w-[560px] my-auto px-6 py-7 md:px-9 md:pt-8 md:pb-7"
        style="box-shadow: 0 24px 80px rgba(0,0,0,0.18);"
        phx-click-away="close_not_a_fit"
        phx-window-keydown="close_not_a_fit"
        phx-key="escape"
        onclick="event.stopPropagation()"
      >
        <div class="flex justify-between items-start gap-3 mb-5">
          <div class="min-w-0">
            <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-1.5 truncate">
              Not a good fit · {@row.name}
            </div>
            <h2 class="font-serif font-normal text-[22px] md:text-[28px] leading-[1.15] tracking-[-0.02em] m-0">
              What makes this a <em>miss</em>?
            </h2>
            <div class="text-[12px] text-ink55 mt-2 leading-[1.55]">
              Tell us in your own words. We'll save it as a rule and apply it
              next time you re-check ICP — no other companies move until you do.
            </div>
          </div>
          <button
            type="button"
            class="w-6 h-6 flex items-center justify-center cursor-pointer"
            phx-click="close_not_a_fit"
          >
            <Liid.icon name="x" size={14} />
          </button>
        </div>

        <form phx-submit="submit_not_a_fit" class="flex flex-col gap-4">
          <textarea
            name="reason"
            autofocus
            placeholder="e.g. They're a pure reseller — we sell to manufacturers, not distributors."
            class="w-full min-h-[120px] px-[16px] py-3 border border-ink20 bg-paperAlt text-[14px] leading-[1.55] text-ink rounded-sharp outline-none resize-y focus:border-ink"
          ></textarea>

          <div :if={@error} class="font-mono text-[11px] text-fail">{@error}</div>

          <div class="flex items-center gap-3 justify-end">
            <Liid.btn size={:small} type="button" phx-click="close_not_a_fit">Cancel</Liid.btn>
            <Liid.btn
              size={:small}
              variant={:primary}
              mono
              type="submit"
              disabled={@saving?}
            >
              {if @saving?, do: "Saving…", else: "Save learning"}
            </Liid.btn>
          </div>
        </form>
      </div>
    </div>
    """
  end

  attr :row, :map, required: true
  attr :calls, :list, required: true
  attr :expanded_id, :string, default: nil

  defp api_calls_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
      style="background: rgba(20,18,14,0.45); backdrop-filter: blur(2px);"
      phx-click="close_api_calls"
    >
      <div
        class="bg-paper border border-ink20 rounded-sharp w-full max-w-[920px] my-auto px-6 py-7 md:px-9 md:pt-8 md:pb-7"
        style="box-shadow: 0 24px 80px rgba(0,0,0,0.18);"
        phx-click-away="close_api_calls"
        phx-window-keydown="close_api_calls"
        phx-key="escape"
        onclick="event.stopPropagation()"
      >
        <div class="flex justify-between items-start gap-3 mb-5">
          <div class="min-w-0">
            <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-1.5 truncate">
              LLM calls · {@row.name}
            </div>
            <h2 class="font-serif font-normal text-[22px] md:text-[28px] leading-[1.15] tracking-[-0.02em] m-0">
              {length(@calls)} recorded calls
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
