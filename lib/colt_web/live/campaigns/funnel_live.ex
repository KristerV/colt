defmodule ColtWeb.Campaigns.FunnelLive do
  @moduledoc """
  View 4 — live funnel. Subscribes to `Colt.Services.Enrichment.Broadcast`,
  patches per-row state on `:stage` and `:row` messages, refreshes the meta
  strip every 4s.
  """
  use ColtWeb, :live_view

  import Ecto.Query

  alias Colt.Filters.IndustryLabels
  alias Colt.Resources.{Campaign, CampaignCompany}
  alias Colt.Services.Enrichment.{Broadcast, Stats}
  alias ColtWeb.Components.{Funnel, Liid}

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  @stage_keys ~w(website icp contact)a

  @tick_ms 4_000

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        rows = load_rows(campaign)
        rows_index = Map.new(rows, &{&1.cc_id, &1})
        stats = compute_stats(rows)

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
            total: length(rows),
            meta: Stats.run(campaign.finalized_at)
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

  defp expand(socket, id), do: replace_row(socket, id, expanded?: true, log: pipeline_log(id))
  defp collapse(socket, id), do: replace_row(socket, id, expanded?: false, log: [])

  defp replace_row(socket, %{} = row) do
    socket
    |> assign(rows_index: Map.put(socket.assigns.rows_index, row.cc_id, row))
    |> stream_insert(:rows, row)
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
        {:failure_detail, v}, acc -> Map.put(acc, :failure_detail, v)
        {:summary, v}, acc -> Map.put(acc, :summary, v)
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
    contact = row.contact || %{name: nil, title: nil, email: nil}
    %{row | contact: Map.put(contact, key, value)}
  end

  defp load_rows(campaign) do
    {:ok, ccs} =
      CampaignCompany.list_for_campaign(campaign.id,
        actor: nil,
        authorize?: false,
        load: [company: [:persons]]
      )

    Enum.map(ccs, &row_for/1)
  end

  defp row_for(cc) do
    company = cc.company
    person = pick_person(company.persons)

    %{
      id: "row-#{cc.id}",
      cc_id: cc.id,
      name: company.name,
      domain: domain_of(company.website_url),
      website_url: company.website_url,
      registry_code: company.registry_code,
      industry: IndustryLabels.label(company.industry_code) || "—",
      size: company.employees_latest,
      growth: company.revenue_growth_bucket,
      status: cc.status,
      failed_stage: cc.failed_stage,
      stages: snapshot_stages(cc.status, cc.failed_stage),
      contact: contact_for(person),
      summary: company.ai_summary,
      rejection_reason: cc.rejection_reason,
      failure_detail: cc.failure_detail,
      expanded?: false,
      log: []
    }
  end

  defp pick_person([]), do: nil

  defp pick_person(persons),
    do: Enum.find(persons, & &1.matches_target_title) || List.first(persons)

  defp contact_for(nil), do: nil

  defp contact_for(p),
    do: %{name: p.name, title: p.title, email: p.email}

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

  defp snapshot_stages(:pending, _), do: idle_stages()
  defp snapshot_stages(:scraping, _), do: idle_stages()
  defp snapshot_stages(:no_website, _), do: stages_up_to(:website, :fall)
  defp snapshot_stages(:rejected, _), do: stages_up_to(:icp, :fall)
  defp snapshot_stages(:no_contacts, _), do: stages_up_to(:contact, :fall)

  defp snapshot_stages(:enriched, _),
    do: %{website: :done, icp: :done, contact: :done}

  defp snapshot_stages(:failed, stage) when stage in @stage_keys,
    do: stages_up_to(stage, :fail)

  defp snapshot_stages(:failed, _), do: idle_stages()
  defp snapshot_stages(_, _), do: idle_stages()

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
      campaign_name={@campaign.name}
      campaign_id={@campaign.id}
    >
      <div class="flex flex-col gap-[18px] flex-1 min-h-0">
        <div class="flex items-end justify-between gap-6">
          <div>
            <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-1.5">
              05 / Funnel · {@campaign.name}
            </div>
            <h1 class="font-serif font-normal text-[44px] leading-none tracking-[-0.02em] m-0">
              Enriching <span style="color: var(--accent);">{@total}</span> companies.
            </h1>
          </div>
          <div class="flex items-center gap-3">
            <Liid.btn size={:small}>
              <Liid.icon name="filter" size={11} /> Filter
            </Liid.btn>
            <Liid.btn size={:small}>
              <Liid.icon name="grid" size={11} /> Columns
            </Liid.btn>
            <Liid.btn size={:small} variant={:primary} mono disabled={@stats.enriched == 0}>
              <Liid.icon name="download" size={11} /> Export
            </Liid.btn>
          </div>
        </div>

        <Funnel.stats_strip stats={@stats} total={@total} />

        <Funnel.meta_strip meta={@meta} visible={@total} total={@total} />

        <div class="flex-1 min-h-0 flex flex-col border border-rule rounded-sharp">
          <Funnel.funnel_header />
          <div class="flex-1 overflow-auto" id="funnel-body" phx-update="stream">
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
    </Layouts.app>
    """
  end
end
