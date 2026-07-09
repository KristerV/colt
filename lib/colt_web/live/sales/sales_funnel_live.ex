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
  alias Colt.Services.Sales.{CreateManualContact, MoveToStage, SeedStages}
  alias Colt.Services.Sending.SendManualReply
  alias ColtWeb.Components.{ContactForm, FunnelThread, Liid}
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
            active_tab: nil,
            reply_html: "",
            reply_nonce: 0,
            note_body: "",
            pending_lost: nil,
            lost_reason: "",
            creating: false,
            create_error: nil,
            contact_form: default_form_values(),
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
        active_tab: nil,
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

      is_nil(contact.thread) ->
        {:noreply,
         assign(socket, error: gettext("This contact has no email thread to reply to."))}

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

    cond do
      is_nil(contact) or is_nil(contact.thread) ->
        {:noreply,
         assign(socket, error: gettext("This contact has no thread to attach a note to."))}

      String.trim(body) == "" ->
        {:noreply, assign(socket, error: gettext("Note is empty."))}

      true ->
        case Note.create(contact.thread.id, body, actor: actor) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(note_body: "", error: nil)
             |> load_thread_data()}

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

  # ── New contact ──────────────────────────────────────────────────────

  def handle_event("open_create", _params, socket) do
    {:noreply,
     assign(socket, creating: true, create_error: nil, contact_form: default_form_values())}
  end

  def handle_event("cancel_create", _params, socket) do
    {:noreply, assign(socket, creating: false, create_error: nil)}
  end

  # Keeps the form values in assigns so a failed submit re-renders with the
  # user's input intact.
  def handle_event("validate_contact", params, socket) do
    {:noreply, assign(socket, contact_form: Map.merge(default_form_values(), params))}
  end

  def handle_event("create_contact", params, socket) do
    values = Map.merge(default_form_values(), params)

    name = String.trim(values["name"] || "")
    company_name = String.trim(values["company_name"] || "")
    registry_code = String.trim(values["registry_code"] || "")
    market = market_atom(values["market"])
    in_sending? = values["in_funnel_sending"] == "on"
    in_sales? = values["in_funnel_sales"] == "on"

    socket = assign(socket, contact_form: values)

    cond do
      name == "" ->
        {:noreply, assign(socket, create_error: gettext("Contact name is required."))}

      company_name == "" or registry_code == "" or is_nil(market) ->
        {:noreply,
         assign(socket,
           create_error: gettext("Company name, reg. code and market are required.")
         )}

      not in_sending? and not in_sales? ->
        {:noreply,
         assign(socket, create_error: gettext("Pick at least one funnel to add them to."))}

      true ->
        attrs = %{
          name: name,
          title: blank_to_nil(values["title"]),
          email: blank_to_nil(values["email"]),
          phone: blank_to_nil(values["phone"]),
          company_name: company_name,
          registry_code: registry_code,
          market: market,
          region: blank_to_nil(values["region"]),
          in_funnel_sending?: in_sending?,
          in_funnel_sales?: in_sales?
        }

        case CreateManualContact.run(socket.assigns.campaign.id, attrs,
               actor: socket.assigns.current_user
             ) do
          {:ok, contact} ->
            {:noreply,
             socket
             |> assign(creating: false, create_error: nil)
             |> load_contacts()
             |> put_flash(:info, gettext("Contact added."))
             |> maybe_open_new_contact(contact)}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               create_error: gettext("Couldn't add contact: %{reason}", reason: inspect(reason))
             )}
        end
    end
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
  # the contact's creation time. One batched query for the whole board (no
  # per-contact N+1).
  defp compute_days_in_stage(contacts) do
    now = DateTime.utc_now()

    thread_ids =
      contacts |> Enum.map(&(&1.thread && &1.thread.id)) |> Enum.reject(&is_nil/1)

    latest_by_thread = latest_stage_change_by_thread(thread_ids)

    Enum.reduce(contacts, %{}, fn c, acc ->
      since =
        case c.thread do
          %{id: tid} -> Map.get(latest_by_thread, tid, c.inserted_at)
          _ -> c.inserted_at
        end

      Map.put(acc, c.id, max(DateTime.diff(now, since, :day), 0))
    end)
  end

  defp latest_stage_change_by_thread([]), do: %{}

  defp latest_stage_change_by_thread(thread_ids) do
    case StatusEvent.stage_changes_for_threads(thread_ids, authorize?: false) do
      # rows come back newest-first, so put_new keeps the latest per thread
      {:ok, events} ->
        Enum.reduce(events, %{}, fn e, acc ->
          Map.put_new(acc, e.thread_id, e.occurred_at)
        end)

      _ ->
        %{}
    end
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

      assign(socket,
        timeline: FunnelThread.build_timeline(outbound, inbound, notes, events),
        thread: thread
      )
    else
      assign(socket, timeline: [], thread: nil)
    end
  end

  defp strip_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&nbsp;", " ")
    |> String.trim()
  end

  defp strip_html(_), do: ""

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # Sales checked by default — this is the sales funnel, so a new lead usually
  # belongs here.
  defp default_form_values do
    %{
      "name" => "",
      "title" => "",
      "email" => "",
      "phone" => "",
      "company_name" => "",
      "registry_code" => "",
      "market" => "ee",
      "region" => "",
      "in_funnel_sales" => "on",
      "in_funnel_sending" => ""
    }
  end

  # Whitelisted string→atom (never String.to_atom on user input); nil if unknown.
  defp market_atom(value) do
    Enum.find(ContactForm.markets(), &(to_string(&1) == value))
  end

  # A sales contact is navigated to so the user lands on the card they just
  # created; a sending-only contact has no sales stage to show, so we stay put.
  defp maybe_open_new_contact(
         socket,
         %{in_funnel_sales?: true, sales_stage_id: stage_id} = contact
       )
       when is_binary(stage_id) do
    push_patch(socket,
      to: ~p"/campaigns/#{socket.assigns.campaign.id}/sales/#{stage_id}/#{contact.id}"
    )
  end

  defp maybe_open_new_contact(socket, _contact), do: socket

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

    entered = length(assigns.contacts)
    won = Enum.count(assigns.contacts, &(&1.sales_stage && &1.sales_stage.kind == :won))
    conversion = if entered > 0, do: round(won / entered * 100), else: nil

    assigns =
      assign(assigns,
        level: level,
        visible: visible,
        entered: entered,
        won: won,
        conversion: conversion
      )

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
            <div class="flex items-center gap-3 shrink-0">
              <button
                type="button"
                phx-click="open_create"
                class="inline-flex items-center gap-1.5 bg-accent text-white rounded-[8px] px-[14px] py-[8px] text-[12.5px] font-semibold cursor-pointer"
                style="box-shadow:0 1px 2px rgba(59,122,224,.3)"
              >
                <span class="text-[15px] leading-none -mt-px">+</span>
                {gettext("New contact")}
              </button>
              <Liid.admin_badge label={gettext("Admin")} />
            </div>
          </div>

          <div class="mt-4">
            <.stage_strip
              stages={@stages}
              contacts={@contacts}
              selected_stage={@selected_stage}
              campaign_id={@campaign.id}
            />
          </div>

          <div
            :if={@conversion != nil}
            class="mt-3 inline-flex items-center gap-4 bg-card border border-border rounded-[8px] px-3.5 py-2.5"
            style="box-shadow:var(--shadow)"
          >
            <div class="flex items-center gap-2 text-[12px] text-inkSoft">
              <span class="font-semibold text-inkSoft">{gettext("Conversion")}</span>
              <b class="text-ink font-bold tabular-nums">{@conversion}%</b>
              <span class="text-inkFaint tabular-nums">({@won}/{@entered} {gettext("won")})</span>
            </div>
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

      <Liid.modal
        :if={@pending_lost}
        id="lost-reason-modal"
        on_cancel="cancel_lost"
        eyebrow={@pending_lost.name}
        title={gettext("Why was this lost?")}
      >
        <form phx-change="set_lost_reason" phx-submit="confirm_lost">
          <input
            type="text"
            name="value"
            value={@lost_reason}
            phx-debounce="150"
            autofocus
            placeholder={gettext("e.g. went with a competitor")}
            class="w-full px-3 py-2.5 border border-border rounded-[8px] text-[14px] outline-none focus:border-accentRing bg-card"
          />
        </form>
        <:footer>
          <Liid.btn size={:small} phx-click="cancel_lost">{gettext("Cancel")}</Liid.btn>
          <button
            phx-click="confirm_lost"
            class="inline-flex items-center gap-1.5 bg-red text-white rounded-[8px] px-[16px] py-[8px] text-[12.5px] font-semibold cursor-pointer"
            style="box-shadow:0 1px 2px rgba(208,90,79,.3)"
          >
            {gettext("Mark lost")}
          </button>
        </:footer>
      </Liid.modal>

      <Liid.modal
        :if={@creating}
        id="new-contact-modal"
        on_cancel="cancel_create"
        eyebrow={gettext("Sales · Funnel")}
        title={gettext("Add a contact")}
        max_width="max-w-[520px]"
      >
        <ContactForm.form id="new-contact-form" values={@contact_form} error={@create_error} />
        <:footer>
          <Liid.btn size={:small} phx-click="cancel_create">{gettext("Cancel")}</Liid.btn>
          <button
            type="submit"
            form="new-contact-form"
            class="inline-flex items-center gap-1.5 bg-accent text-white rounded-[8px] px-[16px] py-[8px] text-[12.5px] font-semibold cursor-pointer"
            style="box-shadow:0 1px 2px rgba(59,122,224,.3)"
          >
            {gettext("Add contact")}
          </button>
        </:footer>
      </Liid.modal>
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
        <span class={["w-[7px] h-[7px] rounded-full shrink-0", Liid.stage_dot(@stage.kind)]} />
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
              {FunnelThread.initials(c.person && c.person.name)}
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
        registry_link: Colt.CompanyRegistry.link(company),
        current_stage: assigns.contact.sales_stage
      )

    ~H"""
    <FunnelThread.thread_pane
      contact={@contact}
      timeline={@timeline}
      recipient={@recipient}
      registry_link={@registry_link}
      active_tab={@active_tab}
      reply_html={@reply_html}
      reply_nonce={@reply_nonce}
      note_body={@note_body}
      error={@error}
    >
      <:actions>
        <button
          type="button"
          phx-click={JS.toggle(to: "#stage-menu-#{@contact.id}")}
          class="inline-flex items-center gap-1.5 rounded-[8px] px-[11px] py-[7px] text-[12.5px] font-semibold cursor-pointer border bg-accentSoft border-accentRing text-accent"
        >
          <span class={[
            "w-[7px] h-[7px] rounded-full",
            Liid.stage_dot(@current_stage && @current_stage.kind)
          ]} />
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
              <span class={["w-[6px] h-[6px] rounded-full shrink-0", Liid.stage_dot(s.kind)]} />
              {s.name}
            </button>
          <% end %>
        </div>
      </:actions>
    </FunnelThread.thread_pane>
    """
  end
end
