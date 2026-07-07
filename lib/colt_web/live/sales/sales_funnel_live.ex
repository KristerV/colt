defmodule ColtWeb.Sales.SalesFunnelLive do
  @moduledoc """
  Sales funnel — a per-campaign, admin-only manual CRM. Cloned from the
  sending funnel's list+thread two-pane: a stage strip on top (the campaign's
  `SalesStage`s with live counts), a left pane of contacts in the selected
  stage (with days-in-stage), and the reused thread pane on the right —
  timeline (emails + notes + StatusEvents) + Reply/Note composer, plus a
  "Move to…" control that moves the contact between stages.
  """

  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, CampaignContact, InboundEmail, Note, OutboundEmail, StatusEvent}
  alias Colt.Services.Sales.{MoveToStage, SeedStages}
  alias Colt.Services.Sending.SendManualReply
  alias ColtWeb.Components.Liid
  alias Phoenix.LiveView.JS
  alias Phoenix.PubSub

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  @pubsub Colt.PubSub

  # Days in a stage past which the row reads as stale.
  @stale_days 14

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        if connected?(socket), do: PubSub.subscribe(@pubsub, "campaign:#{campaign.id}")

        {:ok, stages} = SeedStages.run(campaign.id, actor: actor)

        socket =
          socket
          |> assign(
            page_title: gettext("Sales funnel — %{name}", name: campaign.name),
            campaign: campaign,
            stages: stages,
            selected_stage: nil,
            selected: nil,
            active_tab: :reply,
            reply_html: "",
            reply_nonce: 0,
            note_body: "",
            pending_lost: nil,
            lost_reason: "",
            error: nil,
            timeline: [],
            thread: nil
          )
          |> load_contacts()

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  # Selection lives in the URL: /sales/:stage/:contact_id.
  def handle_params(params, _uri, socket) do
    stage = Enum.find(socket.assigns.stages, &(&1.id == params["stage"]))

    selected =
      case params["contact_id"] do
        nil -> nil
        cid -> Enum.find(socket.assigns.contacts, &(&1.id == cid))
      end

    socket =
      socket
      |> assign(
        selected_stage: stage,
        selected: selected,
        active_tab: :reply,
        reply_html: "",
        note_body: "",
        pending_lost: nil,
        lost_reason: "",
        error: nil
      )
      |> load_thread_data()

    {:noreply, socket}
  end

  # ── Events ───────────────────────────────────────────────────────────

  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in ["reply", "note"] do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  def handle_event("trix_input", %{"value" => v}, socket) do
    {:noreply, assign(socket, reply_html: v)}
  end

  def handle_event("set_note", %{"value" => v}, socket) do
    {:noreply, assign(socket, note_body: v)}
  end

  def handle_event("set_lost_reason", %{"value" => v}, socket) do
    {:noreply, assign(socket, lost_reason: v)}
  end

  def handle_event("send_reply", _params, socket) do
    %{selected: contact, reply_html: html, current_user: actor} = socket.assigns

    cond do
      is_nil(contact) ->
        {:noreply, assign(socket, error: gettext("Pick a contact first."))}

      String.trim(strip_html(html)) == "" ->
        {:noreply, assign(socket, error: gettext("Reply body is empty."))}

      true ->
        case SendManualReply.run(contact.thread.id, html, actor: actor) do
          {:ok, _email} ->
            {:noreply,
             socket
             |> assign(reply_html: "", reply_nonce: socket.assigns.reply_nonce + 1, error: nil)
             |> load_thread_data()
             |> put_flash(:info, gettext("Reply sent."))}

          {:error, reason} ->
            {:noreply,
             assign(socket, error: gettext("Send failed: %{reason}", reason: inspect(reason)))}
        end
    end
  end

  def handle_event("save_note", _params, socket) do
    %{selected: contact, note_body: body, current_user: actor} = socket.assigns

    if is_nil(contact) or String.trim(body) == "" do
      {:noreply, assign(socket, error: gettext("Note is empty."))}
    else
      case Note.create(contact.thread.id, body, actor: actor) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(note_body: "", error: nil)
           |> load_thread_data()
           |> put_flash(:info, gettext("Note saved."))}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             error: gettext("Couldn't save note: %{reason}", reason: inspect(reason))
           )}
      end
    end
  end

  # Moving to a :lost stage first asks for a reason; every other move is
  # immediate.
  def handle_event("move_to_stage", %{"stage" => stage_id}, socket) do
    stage = Enum.find(socket.assigns.stages, &(&1.id == stage_id))

    cond do
      is_nil(stage) or is_nil(socket.assigns.selected) ->
        {:noreply, socket}

      stage.kind == :lost ->
        {:noreply, assign(socket, pending_lost: stage)}

      true ->
        {:noreply, do_move(socket, stage.id, nil)}
    end
  end

  def handle_event("confirm_lost", _params, socket) do
    case socket.assigns.pending_lost do
      %{id: stage_id} ->
        {:noreply,
         socket
         |> do_move(stage_id, socket.assigns.lost_reason)
         |> assign(pending_lost: nil, lost_reason: "")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_lost", _params, socket) do
    {:noreply, assign(socket, pending_lost: nil, lost_reason: "")}
  end

  # ── PubSub ───────────────────────────────────────────────────────────

  def handle_info(msg, socket)
      when is_tuple(msg) and
             elem(msg, 0) in [
               :email_sent,
               :inbound_received,
               :reply_categorized,
               :sequence_halted
             ] do
    {:noreply, socket |> load_contacts() |> keep_selected() |> load_thread_data()}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ── Helpers ──────────────────────────────────────────────────────────

  defp do_move(socket, stage_id, reason) do
    actor = socket.assigns.current_user
    contact = socket.assigns.selected

    case MoveToStage.run(contact.id, stage_id, reason, actor: actor) do
      {:ok, _} ->
        socket
        |> put_flash(:info, gettext("Moved."))
        |> load_contacts()
        |> keep_selected()
        |> load_thread_data()

      {:error, reason} ->
        assign(socket, error: gettext("Couldn't move: %{reason}", reason: inspect(reason)))
    end
  end

  defp load_contacts(socket) do
    actor = socket.assigns.current_user

    contacts =
      case CampaignContact.list_entered_for_campaign(socket.assigns.campaign.id,
             load: [:thread, :sales_stage, person: :company],
             actor: actor
           ) do
        {:ok, rows} -> rows
        _ -> []
      end

    assign(socket, contacts: contacts, days_in_stage: compute_days_in_stage(contacts))
  end

  defp keep_selected(socket) do
    selected_id = socket.assigns.selected && socket.assigns.selected.id

    selected =
      selected_id && Enum.find(socket.assigns.contacts, &(&1.id == selected_id))

    assign(socket, selected: selected)
  end

  # days-in-stage per contact, from the latest stage-move/entry event, else
  # the contact's creation time. Bounded work — contacts are only those in
  # the funnel.
  defp compute_days_in_stage(contacts) do
    now = DateTime.utc_now()

    Enum.reduce(contacts, %{}, fn c, acc ->
      since =
        case c.thread do
          %{id: tid} ->
            case StatusEvent.last_stage_change_for_thread(tid, authorize?: false) do
              {:ok, %{occurred_at: at}} -> at
              _ -> c.inserted_at
            end

          _ ->
            c.inserted_at
        end

      Map.put(acc, c.id, max(DateTime.diff(now, since, :day), 0))
    end)
  end

  defp visible_contacts(_contacts, nil), do: []

  defp visible_contacts(contacts, %{id: stage_id}),
    do: Enum.filter(contacts, &(&1.sales_stage_id == stage_id))

  defp stage_count(contacts, stage_id),
    do: Enum.count(contacts, &(&1.sales_stage_id == stage_id))

  defp load_thread_data(%{assigns: %{selected: nil}} = socket) do
    assign(socket, timeline: [], thread: nil)
  end

  defp load_thread_data(%{assigns: %{selected: contact}} = socket) do
    actor = socket.assigns.current_user
    thread = contact.thread

    if thread do
      outbound = OutboundEmail.list_for_thread!(thread.id, actor: actor, authorize?: true)
      inbound = InboundEmail.list_for_thread!(thread.id, actor: actor, authorize?: true)
      notes = Note.list_for_thread!(thread.id, actor: actor, authorize?: true)
      events = StatusEvent.list_for_thread!(thread.id, load: [:actor], authorize?: false)

      assign(socket, timeline: build_timeline(outbound, inbound, notes, events), thread: thread)
    else
      assign(socket, timeline: [], thread: nil)
    end
  end

  @unscheduled_sentinel ~U[9999-01-01 00:00:00.000000Z]

  defp build_timeline(outbound, inbound, notes, events) do
    out_items =
      outbound
      |> Enum.reject(&(&1.status == :skipped))
      |> Enum.map(fn e ->
        at = outbound_at(e)

        %{
          kind: if(e.is_manual_reply, do: :manual_outbound, else: :outbound),
          at: at,
          sort_at: at || @unscheduled_sentinel,
          sort_pos: e.step_position || 0,
          email: e
        }
      end)

    in_items =
      Enum.map(inbound, fn e ->
        %{kind: :inbound, at: e.received_at, sort_at: e.received_at, sort_pos: 0, email: e}
      end)

    note_items =
      Enum.map(notes, fn n ->
        %{kind: :note, at: n.inserted_at, sort_at: n.inserted_at, sort_pos: 0, note: n}
      end)

    event_items =
      Enum.map(events, fn e ->
        %{kind: :status, at: e.occurred_at, sort_at: e.occurred_at, sort_pos: 0, event: e}
      end)

    (out_items ++ in_items ++ note_items ++ event_items)
    |> Enum.sort_by(&{DateTime.to_unix(&1.sort_at, :microsecond), &1.sort_pos})
  end

  defp outbound_at(%{sent_at: at}) when not is_nil(at), do: at
  defp outbound_at(%{scheduled_at: at}) when not is_nil(at), do: at
  defp outbound_at(_), do: nil

  defp initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
    |> case do
      "" -> "?"
      s -> s
    end
  end

  defp initials(_), do: "?"

  defp website_href("http" <> _ = url), do: url
  defp website_href(url), do: "https://" <> url

  defp website_host(url) do
    case URI.parse(website_href(url)) do
      %URI{host: h} when is_binary(h) -> String.replace_prefix(h, "www.", "")
      _ -> url
    end
  end

  defp strip_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&nbsp;", " ")
    |> String.trim()
  end

  defp strip_html(_), do: ""

  defp body_text(text) when is_binary(text) do
    text
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/[ \t]+\n/, "\n")
    |> String.replace(~r/\n[ \t]+/, "\n")
    |> String.trim()
  end

  defp body_text(_), do: ""

  defp event_transition(%{from: from, to: to}) when is_binary(from) and is_binary(to),
    do: "#{from} → #{to}"

  defp event_transition(%{to: to}) when is_binary(to), do: "→ #{to}"
  defp event_transition(%{from: from}) when is_binary(from), do: from
  defp event_transition(_), do: gettext("status changed")

  defp event_actor(%{actor: %{email: email}}) when not is_nil(email), do: to_string(email)
  defp event_actor(_), do: gettext("System")

  defp kind_dot(:won), do: "bg-green"
  defp kind_dot(:lost), do: "bg-inkFaint"
  defp kind_dot(_), do: "bg-accent"

  defp stale?(days), do: days >= @stale_days

  # ── Render ───────────────────────────────────────────────────────────

  def render(assigns) do
    level =
      cond do
        assigns.selected -> :thread
        assigns.selected_stage -> :list
        true -> :stages
      end

    visible = visible_contacts(assigns.contacts, assigns.selected_stage)

    assigns = assign(assigns, level: level, visible: visible)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:sales_funnel}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="flex flex-col md:h-screen md:-mx-14 md:-my-10">
        <%!-- Mobile back-bar --%>
        <div :if={@level != :stages} class="md:hidden px-2 pt-2 pb-1">
          <.link
            patch={
              if @level == :thread,
                do: ~p"/campaigns/#{@campaign.id}/sales/#{@selected_stage.id}",
                else: ~p"/campaigns/#{@campaign.id}/sales"
            }
            class="inline-flex items-center gap-2 py-2.5 px-2 text-[15px] font-medium text-inkSoft active:text-ink hover:text-ink no-underline"
          >
            <span class="text-[30px] leading-none -mt-0.5">‹</span>
            <span>
              {if @level == :thread,
                do: gettext("Back to %{stage}", stage: @selected_stage.name),
                else: gettext("All stages")}
            </span>
          </.link>
        </div>

        <div class={[
          "px-4 md:px-7 pt-5 md:pt-6 pb-4 flex-none",
          (@level == :stages && "block") || "hidden md:block"
        ]}>
          <div class="flex items-start justify-between gap-4">
            <Liid.headline kicker={gettext("Sales · Funnel")}>
              {raw(gettext("Move the ones who <em class=\"text-accent\">answered</em> forward."))}
            </Liid.headline>
            <Liid.admin_badge label={gettext("Admin")} />
          </div>

          <div class="mt-4">
            <.stage_strip
              stages={@stages}
              contacts={@contacts}
              selected_stage={@selected_stage}
              campaign_id={@campaign.id}
            />
          </div>
        </div>

        <%= if @selected_stage do %>
          <div class="grid grid-cols-1 md:grid-cols-[360px_1fr] flex-1 min-h-0 gap-4 px-0 md:px-7 pb-4 md:pb-6">
            <div class={["min-h-0", (@level == :list && "block") || "hidden", "md:block"]}>
              <.contact_list
                contacts={@visible}
                selected={@selected}
                selected_stage={@selected_stage}
                days_in_stage={@days_in_stage}
                campaign_id={@campaign.id}
              />
            </div>
            <div class={["min-h-0", (@level == :thread && "block") || "hidden", "md:block"]}>
              <%= cond do %>
                <% @selected -> %>
                  <.thread_pane
                    contact={@selected}
                    thread={@thread}
                    timeline={@timeline}
                    stages={@stages}
                    active_tab={@active_tab}
                    reply_html={@reply_html}
                    reply_nonce={@reply_nonce}
                    note_body={@note_body}
                    pending_lost={@pending_lost}
                    lost_reason={@lost_reason}
                    error={@error}
                  />
                <% @visible != [] -> %>
                  <div
                    class="h-full bg-bgSoft border border-border rounded-[11px] flex items-center justify-center text-center px-8"
                    style="box-shadow:var(--shadow-card)"
                  >
                    <div class="text-[14px] text-inkSoft max-w-[300px] leading-[1.55]">
                      {gettext("Select a contact to read the conversation and move them along.")}
                    </div>
                  </div>
                <% true -> %>
                  <.empty_stage stage={@selected_stage} campaign_id={@campaign.id} />
              <% end %>
            </div>
          </div>
        <% else %>
          <div class="hidden md:flex flex-1 items-center justify-center text-center px-8">
            <div class="text-[14px] text-inkSoft max-w-[320px] leading-[1.55]">
              {gettext("Pick a stage above to work its contacts.")}
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # ── Partials ─────────────────────────────────────────────────────────

  attr :stages, :list, required: true
  attr :contacts, :list, required: true
  attr :selected_stage, :any, default: nil
  attr :campaign_id, :string, required: true

  defp stage_strip(assigns) do
    {active, exits} = Enum.split_with(assigns.stages, &(&1.kind == :active))
    assigns = assign(assigns, active: active, exits: exits)

    ~H"""
    <div class="flex flex-col gap-3 md:flex-row md:items-stretch">
      <div class="grid grid-cols-2 sm:grid-cols-3 md:flex md:flex-1 gap-3">
        <.stage_tile
          :for={s <- @active}
          stage={s}
          count={stage_count(@contacts, s.id)}
          active?={@selected_stage != nil and @selected_stage.id == s.id}
          campaign_id={@campaign_id}
        />
      </div>
      <div :if={@exits != []} class="hidden md:block w-px bg-border mx-1" />
      <div class="grid grid-cols-2 md:flex gap-3">
        <.stage_tile
          :for={s <- @exits}
          stage={s}
          count={stage_count(@contacts, s.id)}
          active?={@selected_stage != nil and @selected_stage.id == s.id}
          campaign_id={@campaign_id}
        />
      </div>
    </div>
    """
  end

  attr :stage, :map, required: true
  attr :count, :integer, required: true
  attr :active?, :boolean, default: false
  attr :campaign_id, :string, required: true

  defp stage_tile(assigns) do
    ~H"""
    <.link
      patch={~p"/campaigns/#{@campaign_id}/sales/#{@stage.id}"}
      style={"box-shadow: #{if @active?, do: "0 0 0 1px var(--accentRing), var(--shadow-card)", else: "var(--shadow)"};"}
      class={[
        "no-underline text-left p-[13px] cursor-pointer flex flex-col gap-0.5 min-h-[84px] md:min-w-[112px] rounded-[11px] border transition-colors",
        if(@active?,
          do: "bg-accentSoft border-accentRing",
          else: "bg-card border-border hover:bg-bgSoft"
        )
      ]}
    >
      <div class={[
        "flex items-center gap-1.5 text-[11.5px] font-semibold",
        if(@active?, do: "text-accent", else: "text-inkSoft")
      ]}>
        <span class={["w-[7px] h-[7px] rounded-full shrink-0", kind_dot(@stage.kind)]} />
        <span class="truncate">{@stage.name}</span>
      </div>
      <div class={[
        "text-[27px] font-bold leading-[1.05] tracking-[-0.02em] tabular-nums mt-0.5",
        if(@active?, do: "text-accent", else: "text-ink")
      ]}>
        {@count}
      </div>
      <div class="text-[11px] text-inkFaint">{gettext("contacts")}</div>
    </.link>
    """
  end

  attr :contacts, :list, required: true
  attr :selected, :map, default: nil
  attr :selected_stage, :any, default: nil
  attr :days_in_stage, :map, default: %{}
  attr :campaign_id, :string, required: true

  defp contact_list(assigns) do
    ~H"""
    <div
      class="h-full flex flex-col min-h-0 bg-card border border-border rounded-[11px] overflow-hidden"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="flex-none px-4 py-[13px] border-b border-border flex items-center justify-between">
        <div class="text-[13.5px] font-semibold text-ink">
          <span :if={@selected_stage} class="text-accent">{@selected_stage.name}</span>
        </div>
        <div class="text-[12px] font-medium text-inkFaint tabular-nums">
          {gettext("%{n} contacts", n: length(@contacts))}
        </div>
      </div>
      <div class="flex-1 overflow-y-auto p-2">
        <%= for c <- @contacts do %>
          <% active? = @selected && @selected.id == c.id %>
          <% days = Map.get(@days_in_stage, c.id, 0) %>
          <.link
            patch={~p"/campaigns/#{@campaign_id}/sales/#{@selected_stage.id}/#{c.id}"}
            style={active? && "box-shadow: inset 0 0 0 1px var(--accentRing)"}
            class={[
              "no-underline w-full text-left flex items-center gap-3 px-[11px] py-2.5 rounded-[8px] mb-1 border cursor-pointer",
              if(active?,
                do: "bg-accentSoft border-accentRing",
                else: "bg-transparent border-transparent hover:bg-paperAlt"
              )
            ]}
          >
            <span class={[
              "w-[34px] h-[34px] rounded-[9px] shrink-0 flex items-center justify-center text-[13px] font-semibold",
              if(active?, do: "bg-[#dbe7fa] text-accent", else: "bg-[#ece9e2] text-[#7a6f5f]")
            ]}>
              {initials(c.person && c.person.name)}
            </span>
            <div class="flex-1 min-w-0">
              <div class="text-[13.5px] font-semibold text-ink truncate">
                {(c.person && c.person.name) || "—"}
              </div>
              <div class="text-[12px] text-inkFaint truncate">
                {(c.person && c.person.company && c.person.company.name) ||
                  (c.person && c.person.title) || ""}
              </div>
            </div>
            <span class={[
              "shrink-0 text-[11px] font-semibold rounded-[6px] px-[7px] py-0.5 tabular-nums",
              cond do
                stale?(days) -> "bg-amberSoft text-amber"
                true -> "bg-paperAlt text-inkSoft"
              end
            ]}>
              {gettext("%{n}d", n: days)}
            </span>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end

  attr :stage, :map, required: true
  attr :campaign_id, :string, required: true

  defp empty_stage(assigns) do
    ~H"""
    <div
      class="h-full bg-bgSoft border border-border rounded-[11px] flex flex-col items-center justify-center text-center px-8 py-16 gap-4"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="text-[64px] font-bold leading-none text-ink20">0</div>
      <div class="text-[22px] font-semibold tracking-[-0.01em] text-ink">
        {raw(
          gettext("Nothing in <em class=\"text-accent italic font-semibold\">%{stage}</em> yet.",
            stage: @stage.name
          )
        )}
      </div>
      <div class="text-[13px] text-inkSoft max-w-[360px] leading-[1.55]">
        {gettext("Interested contacts land here automatically, or move them from another stage.")}
      </div>
    </div>
    """
  end

  attr :contact, :map, required: true
  attr :thread, :any, required: true
  attr :timeline, :list, required: true
  attr :stages, :list, required: true
  attr :active_tab, :atom, required: true
  attr :reply_html, :string, required: true
  attr :reply_nonce, :integer, required: true
  attr :note_body, :string, required: true
  attr :pending_lost, :any, default: nil
  attr :lost_reason, :string, default: ""
  attr :error, :any, default: nil

  defp thread_pane(assigns) do
    recipient = (assigns.contact.person && assigns.contact.person.email) || ""
    company = assigns.contact.person && assigns.contact.person.company

    assigns =
      assign(assigns,
        recipient: recipient,
        company: company,
        current_stage: assigns.contact.sales_stage
      )

    ~H"""
    <div class="h-full flex flex-col gap-3 md:gap-3.5 min-h-0 overflow-y-auto md:p-4 md:bg-bgSoft md:border md:border-border md:rounded-[11px] md:[box-shadow:var(--shadow-card)]">
      <div
        class="flex-none bg-card border border-border rounded-[11px] px-4 md:px-5 py-[15px]"
        style="box-shadow:var(--shadow)"
      >
        <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between md:gap-4">
          <div class="flex items-center gap-3 md:gap-3.5 min-w-0">
            <span class="w-[42px] h-[42px] rounded-[11px] shrink-0 flex items-center justify-center text-[16px] font-bold bg-[#dbe7fa] text-accent">
              {initials(@contact.person && @contact.person.name)}
            </span>
            <div class="min-w-0">
              <div class="text-[17px] font-bold tracking-[-0.01em] text-ink truncate">
                {(@contact.person && @contact.person.name) || "—"}
              </div>
              <div
                :if={@contact.person && @contact.person.title}
                class="text-[12.5px] text-inkSoft mt-0.5"
              >
                {@contact.person.title}
              </div>
              <div class="text-[12px] text-accent font-medium mt-0.5 break-all">{@recipient}</div>
              <div :if={@company} class="mt-2 text-[12px] text-inkSoft">
                <div class="font-semibold text-ink">{@company.name}</div>
                <div class="flex flex-wrap gap-x-3 gap-y-1 mt-1">
                  <a
                    :if={@contact.person && @contact.person.phone}
                    href={"tel:#{@contact.person.phone}"}
                    class="text-accent font-medium hover:underline"
                  >
                    ☎ {@contact.person.phone}
                  </a>
                  <a
                    :if={@company.website_url}
                    href={website_href(@company.website_url)}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="text-accent font-medium hover:underline"
                  >
                    ↗ {website_host(@company.website_url)}
                  </a>
                </div>
              </div>
            </div>
          </div>

          <div class="flex items-center gap-2.5 flex-wrap shrink-0 relative">
            <button
              type="button"
              phx-click={JS.toggle(to: "#stage-menu-#{@contact.id}")}
              class="inline-flex items-center gap-1.5 rounded-[8px] px-[11px] py-[7px] text-[12.5px] font-semibold cursor-pointer border bg-accentSoft border-accentRing text-accent"
            >
              <span class={["w-[7px] h-[7px] rounded-full", kind_dot(@current_stage && @current_stage.kind)]} />
              {(@current_stage && @current_stage.name) || gettext("Move to…")}
              <span class="opacity-70 text-[10px]">▾</span>
            </button>
            <div
              id={"stage-menu-#{@contact.id}"}
              class="hidden absolute right-0 top-full mt-1 bg-card border border-border rounded-[8px] z-20 min-w-[200px] py-1"
              style="box-shadow:var(--shadow-card)"
              phx-click-away={JS.hide(to: "#stage-menu-#{@contact.id}")}
            >
              <%= for s <- @stages do %>
                <button
                  phx-click={
                    JS.push("move_to_stage", value: %{stage: s.id})
                    |> JS.hide(to: "#stage-menu-#{@contact.id}")
                  }
                  class={[
                    "flex items-center gap-2 w-full text-left px-3 py-2 text-[12.5px] hover:bg-paperAlt",
                    if(@current_stage && @current_stage.id == s.id,
                      do: "text-accent font-semibold",
                      else: "text-inkSoft"
                    )
                  ]}
                >
                  <span class={["w-[6px] h-[6px] rounded-full shrink-0", kind_dot(s.kind)]} />
                  {s.name}
                </button>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Lost-reason prompt --%>
        <div
          :if={@pending_lost}
          class="mt-3 bg-redSoft border border-red/30 rounded-[8px] px-3.5 py-3"
        >
          <div class="text-[12.5px] font-semibold text-red mb-2">
            {gettext("Why lost? (moving to %{stage})", stage: @pending_lost.name)}
          </div>
          <form phx-change="set_lost_reason">
            <input
              type="text"
              name="value"
              value={@lost_reason}
              phx-debounce="200"
              placeholder={gettext("e.g. went with a competitor")}
              class="w-full px-3 py-2 border border-border rounded-[8px] text-[13px] outline-none focus:border-accentRing bg-card"
            />
          </form>
          <div class="mt-2.5 flex justify-end gap-2">
            <Liid.btn size={:small} phx-click="cancel_lost">{gettext("Cancel")}</Liid.btn>
            <button
              phx-click="confirm_lost"
              class="inline-flex items-center gap-1.5 bg-red text-white rounded-[8px] px-[14px] py-[7px] text-[12px] font-semibold cursor-pointer"
            >
              {gettext("Mark lost")}
            </button>
          </div>
        </div>
      </div>

      <%= if @timeline == [] do %>
        <div
          class="flex-none bg-card border border-border rounded-[11px] px-5 py-4 text-[12.5px] text-inkFaint"
          style="box-shadow:var(--shadow)"
        >
          {gettext("No messages yet.")}
        </div>
      <% else %>
        <%= for item <- @timeline do %>
          <.timeline_item item={item} />
        <% end %>
      <% end %>

      <.composer
        active_tab={@active_tab}
        reply_html={@reply_html}
        reply_nonce={@reply_nonce}
        note_body={@note_body}
        recipient={@recipient}
        error={@error}
      />
    </div>
    """
  end

  attr :item, :map, required: true

  defp timeline_item(%{item: %{kind: :status}} = assigns) do
    event = assigns.item.event

    assigns =
      assign(assigns,
        transition: event_transition(event),
        actor_label: event_actor(event),
        reason: event.reason
      )

    ~H"""
    <div class="flex-none flex justify-center">
      <div
        class="w-full md:w-[72%] max-w-[520px] bg-paperAlt border border-border rounded-[8px] px-3.5 py-2"
        style="box-shadow:var(--shadow)"
      >
        <div class="flex items-center gap-2">
          <span class="w-[5px] h-[5px] rounded-full bg-inkFaint shrink-0" />
          <span class="text-[12px] font-medium text-inkSoft tabular-nums">{@transition}</span>
          <span class="text-[11px] text-inkFaint truncate">· {@actor_label}</span>
          <span :if={@item.at} class="ml-auto shrink-0 text-[11px] text-inkFaint tabular-nums">
            {Calendar.strftime(@item.at, "%b %d · %H:%M")}
          </span>
        </div>
        <div :if={@reason} class="mt-1 pl-[13px] text-[11.5px] text-inkFaint leading-[1.45]">
          {@reason}
        </div>
      </div>
    </div>
    """
  end

  defp timeline_item(%{item: %{kind: :note}} = assigns) do
    ~H"""
    <div class="flex-none flex justify-center">
      <div
        class="w-full md:w-[72%] max-w-[520px] bg-amberSoft border border-[#f0dcb0] rounded-[11px] overflow-hidden"
        style="box-shadow:var(--shadow)"
      >
        <div class="flex items-center gap-2 px-3.5 py-[9px] bg-[#f7ecd2] border-b border-[#f0dcb0]">
          <span class="inline-flex items-center text-[11px] font-semibold px-2 py-[3px] rounded-[6px] bg-[#efd9a8] text-[#9a6f17]">
            {gettext("Note")}
          </span>
          <span class="ml-auto text-[11px] font-medium text-[#9a6f17] tabular-nums">
            {Calendar.strftime(@item.at, "%b %d · %H:%M")}
          </span>
        </div>
        <div
          phx-no-format
          class="px-[15px] py-3 text-[13px] leading-[1.55] font-medium text-[#6e5417] whitespace-pre-wrap"
        >{@item.note.body}</div>
      </div>
    </div>
    """
  end

  defp timeline_item(%{item: %{kind: kind}} = assigns)
       when kind in [:outbound, :manual_outbound, :inbound] do
    outbound? = kind in [:outbound, :manual_outbound]
    inbound? = kind == :inbound
    manual? = kind == :manual_outbound
    status = if outbound?, do: assigns.item.email.status, else: nil
    sent? = outbound? and status == :sent

    step_chip =
      cond do
        manual? -> gettext("Reply · You")
        outbound? -> gettext("Step %{n}", n: (assigns.item.email.step_position || 0) + 1)
        true -> gettext("Reply")
      end

    body =
      if inbound?,
        do: assigns.item.email.body,
        else: assigns.item.email.user_body || assigns.item.email.ai_body || ""

    subject =
      if inbound?,
        do: assigns.item.email.subject,
        else: assigns.item.email.user_subject || assigns.item.email.ai_subject

    sender = if inbound?, do: assigns.item.email.from_address, else: gettext("You")

    assigns =
      assign(assigns,
        outbound?: outbound?,
        inbound?: inbound?,
        manual?: manual?,
        sent?: sent?,
        step_chip: step_chip,
        body: body,
        subject: subject,
        sender: sender
      )

    ~H"""
    <div class={["flex-none flex", if(@outbound?, do: "md:justify-start", else: "md:justify-end")]}>
      <div
        class={[
          "w-full md:w-[90%] max-w-[680px] bg-card rounded-[11px] overflow-hidden border",
          if(@inbound?, do: "border-[#cdddf3]", else: "border-border")
        ]}
        style="box-shadow:var(--shadow)"
      >
        <div class={[
          "flex items-center gap-2 flex-wrap px-3.5 py-[9px] border-b",
          if(@inbound?, do: "bg-accentSoft border-[#dbe7fa]", else: "bg-bgSoft border-border")
        ]}>
          <span class={[
            "inline-flex items-center text-[11px] font-semibold px-2 py-[3px] rounded-[6px]",
            if(@inbound?, do: "bg-[#dbe7fa] text-accent", else: "bg-[#efece6] text-inkSoft")
          ]}>
            {@step_chip}
          </span>
          <span class={[
            "inline-flex items-center text-[11px] font-semibold px-2 py-[3px] rounded-[6px]",
            if(@inbound?, do: "bg-[#dbe7fa] text-accent", else: "bg-accentSoft text-accent")
          ]}>
            {@sender}
          </span>
          <span
            :if={@sent?}
            class="inline-flex items-center text-[11px] font-semibold px-2 py-[3px] rounded-[6px] bg-greenSoft text-green"
          >
            {gettext("Sent")}
          </span>
          <span :if={@item.at} class="ml-auto text-[11px] font-medium text-inkFaint tabular-nums">
            {Calendar.strftime(@item.at, "%b %d · %H:%M")}
          </span>
        </div>
        <div class="px-[15px] py-3.5">
          <div :if={@subject} class="text-[13.5px] font-bold tracking-[-0.005em] text-ink mb-1.5">
            {@subject}
          </div>
          <div phx-no-format class="text-[13px] leading-[1.55] text-[#4a473f] whitespace-pre-wrap">{body_text(@body)}</div>
        </div>
      </div>
    </div>
    """
  end

  attr :active_tab, :atom, required: true
  attr :reply_html, :string, required: true
  attr :reply_nonce, :integer, required: true
  attr :note_body, :string, required: true
  attr :recipient, :string, required: true
  attr :error, :any, default: nil

  defp composer(assigns) do
    ~H"""
    <div
      class="flex-none bg-card border border-border rounded-[11px] overflow-hidden"
      style="box-shadow:var(--shadow)"
    >
      <div class="flex items-center gap-1 px-2.5 py-2 border-b border-border bg-bgSoft">
        <button
          phx-click="switch_tab"
          phx-value-tab="reply"
          style={@active_tab == :reply && "box-shadow: inset 0 0 0 1px var(--accentRing)"}
          class={[
            "text-[12.5px] font-semibold px-3 py-1.5 rounded-[7px] cursor-pointer",
            if(@active_tab == :reply, do: "bg-accentSoft text-accent", else: "text-inkFaint")
          ]}
        >
          {gettext("Reply")}
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="note"
          style={@active_tab == :note && "box-shadow: inset 0 0 0 1px var(--accentRing)"}
          class={[
            "text-[12.5px] font-semibold px-3 py-1.5 rounded-[7px] cursor-pointer",
            if(@active_tab == :note, do: "bg-accentSoft text-accent", else: "text-inkFaint")
          ]}
        >
          {gettext("Note")}
        </button>
        <span
          :if={@active_tab == :reply}
          class="ml-auto text-[12px] text-inkFaint font-medium truncate"
        >
          {gettext("To:")} <b class="text-inkSoft font-semibold">{@recipient}</b>
        </span>
      </div>

      <div :if={@error} class="px-3.5 pt-3 text-[12px] text-red">{@error}</div>

      <div
        :if={@active_tab == :reply}
        class="px-3.5 py-3"
        id={"trix-wrap-#{@reply_nonce}"}
        phx-hook="TrixEditor"
        phx-update="ignore"
      >
        <input id={"trix-content-#{@reply_nonce}"} type="hidden" value={@reply_html} />
        <trix-editor input={"trix-content-#{@reply_nonce}"} class="trix-content" style="min-height:120px;">
        </trix-editor>
        <div class="mt-3 flex justify-end">
          <button
            phx-click="send_reply"
            class="inline-flex items-center gap-1.5 bg-accent text-white rounded-[8px] px-[18px] py-[9px] text-[13px] font-semibold cursor-pointer"
            style="box-shadow:0 1px 2px rgba(59,122,224,.3)"
          >
            <Liid.icon name="arrow" size={11} /> {gettext("Send reply")}
          </button>
        </div>
      </div>

      <div :if={@active_tab == :note} class="px-3.5 py-3">
        <form id={"note-form-#{@reply_nonce}"} phx-change="set_note">
          <textarea
            id={"note-input-#{@reply_nonce}"}
            name="value"
            rows="4"
            phx-debounce="300"
            placeholder={gettext("Internal note — not sent to recipient.")}
            class="w-full px-3 py-2 border border-border rounded-[8px] text-[13px] outline-none resize-none focus:border-accentRing"
          >{@note_body}</textarea>
        </form>
        <div class="mt-3 flex justify-end">
          <button
            phx-click="save_note"
            class="inline-flex items-center gap-1.5 bg-accent text-white rounded-[8px] px-[18px] py-[9px] text-[13px] font-semibold cursor-pointer"
            style="box-shadow:0 1px 2px rgba(59,122,224,.3)"
          >
            {gettext("Save note")}
          </button>
        </div>
      </div>
    </div>
    """
  end
end
