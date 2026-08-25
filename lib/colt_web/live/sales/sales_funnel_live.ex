defmodule ColtWeb.Sales.SalesFunnelLive do
  @moduledoc """
  Sales funnel — a per-campaign, admin-only manual CRM, shaped as a work queue
  rather than a board of hand-typed stages.

  The four buckets are **derived**, never set directly: `Now` (overdue, due
  today, or never triaged), `Later` (a next action dated ahead), and the `Won`
  / `Lost` exits. See `Colt.Resources.CampaignContact.Calculations.SalesBucket`
  — a contact only ever moves by being given a date or an outcome, which is
  what makes "who needs me today?" answerable at a glance.

  Layout is the sending funnel's list+thread two-pane: bucket strip on top, a
  left pane of contacts in the selected bucket (each with a date chip), and the
  reused thread pane on the right — timeline, composer, the campaign checklist,
  and the `Next action` / `Won` / `Lost` controls.
  """

  use ColtWeb, :live_view

  alias Colt.Accounts

  alias Colt.Resources.{
    Campaign,
    CampaignContact,
    ChecklistItem,
    ContactChecklistItem,
    EmailAccount,
    InboundEmail,
    Note,
    OutboundEmail,
    StatusEvent
  }

  alias Colt.SalesClock

  alias Colt.Services.Sales.{
    AssignContact,
    CreateManualContact,
    SetChecklistItem,
    SetNextAction,
    SetOutcome,
    UpdateContact
  }

  alias Colt.Services.Export.ThreadTranscript
  alias Colt.Services.Sending.SendManualReply
  alias ColtWeb.Components.{ContactForm, FunnelThread, Liid}
  alias ColtWeb.Deck.Slides
  alias Phoenix.LiveView.JS
  alias Phoenix.PubSub

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  @pubsub Colt.PubSub

  # The board's columns. Fixed, not user-defined — they're derived from each
  # contact's next action date and outcome.
  @buckets [:now, :later, :won, :lost]
  @exits [:won, :lost]

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        if connected?(socket), do: PubSub.subscribe(@pubsub, "campaign:#{campaign.id}")

        socket =
          socket
          |> assign(
            page_title: gettext("Sales funnel — %{name}", name: campaign.name),
            campaign: campaign,
            checklist: load_checklist(campaign.id, actor),
            ticks: %{},
            selected_bucket: nil,
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
            editing: false,
            edit_error: nil,
            edit_form: default_form_values(),
            email_accounts: load_email_account_options(actor),
            assignable_users: load_assignable_users(),
            error: nil,
            timeline: [],
            thread: nil,
            transcript: ""
          )
          |> load_contacts()

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  # Selection lives in the URL: /sales/:bucket/:contact_id.
  def handle_params(params, _uri, socket) do
    bucket = parse_bucket(params["bucket"])

    selected =
      case params["contact_id"] do
        nil -> nil
        cid -> Enum.find(socket.assigns.contacts, &(&1.id == cid))
      end

    socket =
      socket
      |> assign(
        selected_bucket: bucket,
        selected: selected,
        active_tab: nil,
        reply_html: "",
        note_body: "",
        pending_lost: false,
        lost_reason: "",
        error: nil
      )
      |> load_thread_data()

    {:noreply, socket}
  end

  # Whitelisted slug→atom; unknown slugs fall back to "no bucket selected"
  # rather than raising on a hand-typed URL.
  defp parse_bucket(slug), do: Enum.find(@buckets, &(to_string(&1) == slug))

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

  # ── Next action ──────────────────────────────────────────────────────

  # Presets are resolved server-side (see `next_action_groups/0`) so "3 days"
  # means three days in the funnel's timezone, not the browser's — the button
  # just relays back the exact ISO date already computed for it, same as the
  # date picker below.
  def handle_event("next_action_on", %{"value" => value}, socket) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:noreply, do_set_next_action(socket, SalesClock.at_start_of_workday(date))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear_next_action", _params, socket) do
    {:noreply, do_set_next_action(socket, nil)}
  end

  # ── Outcome ──────────────────────────────────────────────────────────

  # Lost asks for a reason first; won and reopen are immediate.
  def handle_event("set_outcome", %{"outcome" => "lost"}, socket) do
    if socket.assigns.selected,
      do: {:noreply, assign(socket, pending_lost: true)},
      else: {:noreply, socket}
  end

  def handle_event("set_outcome", %{"outcome" => "won"}, socket) do
    {:noreply, do_set_outcome(socket, :won, nil)}
  end

  def handle_event("set_outcome", %{"outcome" => "reopen"}, socket) do
    {:noreply, do_set_outcome(socket, nil, nil)}
  end

  def handle_event("confirm_lost", _params, socket) do
    if socket.assigns.pending_lost do
      {:noreply,
       socket
       |> do_set_outcome(:lost, socket.assigns.lost_reason)
       |> assign(pending_lost: false, lost_reason: "")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_lost", _params, socket) do
    {:noreply, assign(socket, pending_lost: false, lost_reason: "")}
  end

  # ── Assign ───────────────────────────────────────────────────────────

  def handle_event("assign", %{"user_id" => user_id}, socket) do
    case socket.assigns.selected do
      nil ->
        {:noreply, socket}

      contact ->
        case AssignContact.run(contact.id, user_id, actor: socket.assigns.current_user) do
          {:ok, _} ->
            {:noreply, socket |> load_contacts() |> keep_selected() |> load_thread_data()}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               error: gettext("Couldn't assign: %{reason}", reason: inspect(reason))
             )}
        end
    end
  end

  # ── Checklist ────────────────────────────────────────────────────────

  def handle_event("toggle_checklist", %{"item" => item_id}, socket) do
    contact = socket.assigns.selected
    done? = not ticked?(socket.assigns.ticks, item_id)

    if contact do
      case SetChecklistItem.run(contact.id, item_id, done?, actor: socket.assigns.current_user) do
        {:ok, _} ->
          {:noreply, socket |> load_thread_data()}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             error: gettext("Couldn't update the checklist: %{reason}", reason: inspect(reason))
           )}
      end
    else
      {:noreply, socket}
    end
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
          website: blank_to_nil(values["website"]),
          assigned_email_account_id: blank_to_nil(values["assigned_email_account_id"]),
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

  # ── Edit contact ─────────────────────────────────────────────────────

  def handle_event("open_edit", _params, socket) do
    case socket.assigns.selected do
      nil ->
        {:noreply, socket}

      contact ->
        {:noreply,
         assign(socket,
           editing: true,
           edit_error: nil,
           edit_form: form_values_from_contact(contact)
         )}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: false, edit_error: nil)}
  end

  def handle_event("validate_edit", params, socket) do
    {:noreply, assign(socket, edit_form: merge_edit_params(socket.assigns.edit_form, params))}
  end

  def handle_event("update_contact", params, socket) do
    contact = socket.assigns.selected
    values = merge_edit_params(socket.assigns.edit_form, params)

    name = String.trim(values["name"] || "")
    company_name = String.trim(values["company_name"] || "")
    registry_code = String.trim(values["registry_code"] || "")
    market = market_atom(values["market"])
    in_sending? = values["in_funnel_sending"] == "on"
    in_sales? = values["in_funnel_sales"] == "on"

    # Company fields are only editable (and only validated) for manual contacts;
    # an enrichment contact's company block is locked, so it's never rewritten.
    company_editable? = contact != nil and contact.origin == :manual

    socket = assign(socket, edit_form: values)

    cond do
      is_nil(contact) ->
        {:noreply, assign(socket, editing: false)}

      name == "" ->
        {:noreply, assign(socket, edit_error: gettext("Contact name is required."))}

      company_editable? and (company_name == "" or registry_code == "" or is_nil(market)) ->
        {:noreply,
         assign(socket,
           edit_error: gettext("Company name, reg. code and market are required.")
         )}

      not in_sending? and not in_sales? ->
        {:noreply,
         assign(socket, edit_error: gettext("Pick at least one funnel to keep them in."))}

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
          website: blank_to_nil(values["website"]),
          assigned_email_account_id: blank_to_nil(values["assigned_email_account_id"]),
          in_funnel_sending?: in_sending?,
          in_funnel_sales?: in_sales?
        }

        case UpdateContact.run(contact, attrs, actor: socket.assigns.current_user) do
          {:ok, _contact} ->
            {:noreply,
             socket
             |> assign(editing: false, edit_error: nil)
             |> load_contacts()
             |> keep_selected()
             |> load_thread_data()
             |> put_flash(:info, gettext("Contact updated."))}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               edit_error: gettext("Couldn't update contact: %{reason}", reason: inspect(reason))
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

  defp do_set_next_action(%{assigns: %{selected: nil}} = socket, _at), do: socket

  defp do_set_next_action(socket, at) do
    contact = socket.assigns.selected

    case SetNextAction.run(contact.id, at, actor: socket.assigns.current_user) do
      {:ok, _} ->
        socket
        |> put_flash(:info, next_action_flash(at))
        |> refresh()

      {:error, reason} ->
        assign(socket,
          error: gettext("Couldn't set the date: %{reason}", reason: inspect(reason))
        )
    end
  end

  defp next_action_flash(nil), do: gettext("Next action cleared — back in Now.")

  defp next_action_flash(at),
    do: gettext("Next action set for %{date}.", date: SalesClock.to_local_date(at))

  defp do_set_outcome(%{assigns: %{selected: nil}} = socket, _outcome, _reason), do: socket

  defp do_set_outcome(socket, outcome, reason) do
    contact = socket.assigns.selected

    case SetOutcome.run(contact.id, outcome, reason: reason, actor: socket.assigns.current_user) do
      {:ok, _} ->
        socket
        |> put_flash(:info, outcome_flash(outcome))
        |> refresh()

      {:error, err} ->
        assign(socket, error: gettext("Couldn't save: %{reason}", reason: inspect(err)))
    end
  end

  defp outcome_flash(:won), do: gettext("Marked won.")
  defp outcome_flash(:lost), do: gettext("Marked lost.")
  defp outcome_flash(nil), do: gettext("Reopened — back in Now.")

  # A contact whose bucket just changed is no longer in the list the URL
  # points at, so reload everything and re-resolve the selection.
  defp refresh(socket) do
    socket |> load_contacts() |> keep_selected() |> load_thread_data()
  end

  defp load_checklist(campaign_id, actor) do
    case ChecklistItem.list_for_campaign(campaign_id, actor: actor) do
      {:ok, rows} -> rows
      _ -> []
    end
  end

  defp load_contacts(socket) do
    actor = socket.assigns.current_user

    contacts =
      case CampaignContact.list_for_sales_funnel(socket.assigns.campaign.id,
             load: [
               :sales_bucket,
               :thread,
               :assigned_email_account,
               :assigned_to,
               person: :company
             ],
             actor: actor
           ) do
        {:ok, rows} -> rows
        _ -> []
      end

    assign(socket, contacts: contacts)
  end

  defp keep_selected(socket) do
    selected_id = socket.assigns.selected && socket.assigns.selected.id

    selected =
      selected_id && Enum.find(socket.assigns.contacts, &(&1.id == selected_id))

    assign(socket, selected: selected)
  end

  defp visible_contacts(_contacts, nil), do: []

  # Open buckets keep the query's date order (most overdue first, undated
  # last); the closed ones read better most-recently-closed first.
  defp visible_contacts(contacts, bucket) when bucket in @exits do
    contacts
    |> Enum.filter(&(&1.sales_bucket == bucket))
    |> Enum.sort_by(& &1.outcome_at, {:desc, DateTime})
  end

  defp visible_contacts(contacts, bucket),
    do: Enum.filter(contacts, &(&1.sales_bucket == bucket))

  defp bucket_count(contacts, bucket),
    do: Enum.count(contacts, &(&1.sales_bucket == bucket))

  defp bucket_label(:now), do: gettext("Now")
  defp bucket_label(:later), do: gettext("Later")
  defp bucket_label(:won), do: gettext("Won")
  defp bucket_label(:lost), do: gettext("Lost")

  defp bucket_dot(:now), do: "bg-accent"
  defp bucket_dot(:won), do: "bg-green"
  defp bucket_dot(_), do: "bg-inkFaint"

  # The date chip on each row. Overdue is the only thing loud enough to warrant
  # amber — everything else is informational.
  defp row_chip(%{sales_bucket: bucket, outcome_at: at}) when bucket in @exits do
    {format_date(at), "bg-paperAlt text-inkSoft"}
  end

  defp row_chip(%{next_action_at: nil}), do: {gettext("No date"), "bg-paperAlt text-inkFaint"}

  defp row_chip(%{next_action_at: at}) do
    case SalesClock.days_from_today(at) do
      0 -> {gettext("Today"), "bg-accentSoft text-accent"}
      n when n < 0 -> {gettext("%{n}d overdue", n: abs(n)), "bg-amberSoft text-amber"}
      n -> {gettext("in %{n}d", n: n), "bg-paperAlt text-inkSoft"}
    end
  end

  defp format_date(nil), do: "—"
  defp format_date(%DateTime{} = at), do: at |> SalesClock.to_local_date() |> Date.to_iso8601()

  defp ticked?(ticks, item_id), do: Map.get(ticks, item_id) != nil

  defp done_count(ticks), do: ticks |> Map.values() |> Enum.count(&(&1 != nil))

  defp load_thread_data(%{assigns: %{selected: nil}} = socket) do
    assign(socket, timeline: [], thread: nil, ticks: %{}, transcript: "")
  end

  defp load_thread_data(%{assigns: %{selected: contact}} = socket) do
    actor = socket.assigns.current_user
    thread = contact.thread
    socket = assign(socket, ticks: load_ticks(contact.id, actor))

    if thread do
      outbound = OutboundEmail.list_for_thread!(thread.id, actor: actor, authorize?: true)
      inbound = InboundEmail.list_for_thread!(thread.id, actor: actor, authorize?: true)
      notes = Note.list_for_thread!(thread.id, actor: actor, authorize?: true)
      events = StatusEvent.list_for_thread!(thread.id, load: [:actor], authorize?: false)

      timeline = FunnelThread.build_timeline(outbound, inbound, notes, events)
      {:ok, transcript} = ThreadTranscript.run(contact, timeline)

      assign(socket, timeline: timeline, thread: thread, transcript: transcript)
    else
      assign(socket, timeline: [], thread: nil, transcript: "")
    end
  end

  # checklist_item_id => done_at (or nil for an unticked row). Only ticked
  # items have rows at all, so an untouched contact costs one empty query.
  defp load_ticks(contact_id, actor) do
    case ContactChecklistItem.list_for_contact(contact_id, actor: actor) do
      {:ok, rows} -> Map.new(rows, &{&1.checklist_item_id, &1.done_at})
      _ -> %{}
    end
  end

  defp strip_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&nbsp;", " ")
    |> String.trim()
  end

  defp strip_html(_), do: ""

  # "Send from" options — the current user's connected, sendable inboxes. The
  # picker seeds the same sticky `assigned_email_account_id` the sending
  # pipeline uses; there is no manual-only send path.
  defp load_email_account_options(actor) do
    case EmailAccount.list_healthy_for_user(actor.id, actor: actor) do
      {:ok, rows} -> Enum.map(rows, &%{id: &1.id, label: &1.address})
      _ -> []
    end
  end

  # Who the assign picker can hand a contact to — admins only, since they're
  # the only ones who work this funnel.
  defp load_assignable_users do
    Accounts.list_users!(authorize?: false)
    |> Enum.filter(& &1.is_admin)
    |> Enum.sort_by(& &1.email)
  end

  defp sender_label(%{assigned_email_account: %{address: address}}), do: address
  defp sender_label(_), do: nil

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
      "website" => "",
      "assigned_email_account_id" => "",
      "in_funnel_sales" => "on",
      "in_funnel_sending" => ""
    }
  end

  # Prefill the shared contact form from an existing contact for editing.
  defp form_values_from_contact(contact) do
    person = contact.person
    company = person && person.company

    %{
      "name" => (person && person.name) || "",
      "title" => (person && person.title) || "",
      "email" => (person && person.email) || "",
      "phone" => (person && person.phone) || "",
      "company_name" => (company && company.name) || "",
      "registry_code" => (company && company.registry_code) || "",
      "market" => (company && to_string(company.market)) || "ee",
      "region" => (company && company.region) || "",
      "website" => (company && company.website_url) || "",
      "assigned_email_account_id" => contact.assigned_email_account_id || "",
      "in_funnel_sales" => if(contact.in_funnel_sales?, do: "on", else: ""),
      "in_funnel_sending" => if(contact.in_funnel_sending?, do: "on", else: "")
    }
  end

  # Merge a change/submit payload over the current edit form. Starts from the
  # existing values (so a locked, non-submitting company block keeps its
  # display), but resets the checkboxes first — unchecked boxes are absent from
  # params, so without the reset they could never be turned off.
  defp merge_edit_params(current, params) do
    current
    |> Map.put("in_funnel_sending", "")
    |> Map.put("in_funnel_sales", "")
    |> Map.merge(params)
  end

  # Whitelisted string→atom (never String.to_atom on user input); nil if unknown.
  defp market_atom(value) do
    Enum.find(ContactForm.markets(), &(to_string(&1) == value))
  end

  # A sales contact is navigated to so the user lands on the card they just
  # created. They enter untriaged, so that's always the Now bucket. A
  # sending-only contact isn't on this board at all, so we stay put.
  defp maybe_open_new_contact(socket, %{in_funnel_sales?: true} = contact) do
    push_patch(socket, to: ~p"/campaigns/#{socket.assigns.campaign.id}/sales/now/#{contact.id}")
  end

  defp maybe_open_new_contact(socket, _contact), do: socket

  # ── Render ───────────────────────────────────────────────────────────

  def render(assigns) do
    level =
      cond do
        assigns.selected -> :thread
        assigns.selected_bucket -> :list
        true -> :buckets
      end

    assigns =
      assign(assigns,
        level: level,
        visible: visible_contacts(assigns.contacts, assigns.selected_bucket)
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
        <div :if={@level != :buckets} class="md:hidden px-2 pt-2 pb-1">
          <.link
            patch={
              if @level == :thread,
                do: ~p"/campaigns/#{@campaign.id}/sales/#{@selected_bucket}",
                else: ~p"/campaigns/#{@campaign.id}/sales"
            }
            class="inline-flex items-center gap-2 py-2.5 px-2 text-[15px] font-medium text-inkSoft active:text-ink hover:text-ink no-underline"
          >
            <span class="text-[30px] leading-none -mt-0.5">‹</span>
            <span>
              {if @level == :thread,
                do: gettext("Back to %{bucket}", bucket: bucket_label(@selected_bucket)),
                else: gettext("All contacts")}
            </span>
          </.link>
        </div>

        <div class={[
          "px-4 md:px-7 pt-5 md:pt-6 pb-4 flex-none",
          (@level == :buckets && "block") || "hidden md:block"
        ]}>
          <div class="flex items-start justify-between gap-4">
            <Liid.headline kicker={gettext("Sales · Funnel")}>
              {raw(gettext("Who needs you <em class=\"text-accent\">today</em>."))}
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
            <.bucket_strip
              contacts={@contacts}
              selected_bucket={@selected_bucket}
              campaign_id={@campaign.id}
            />
          </div>
        </div>

        <%= if @selected_bucket do %>
          <div class="grid grid-cols-1 md:grid-cols-[360px_1fr] flex-1 min-h-0 gap-4 px-0 md:px-7 pb-4 md:pb-6">
            <div class={["min-h-0", (@level == :list && "block") || "hidden", "md:block"]}>
              <.contact_list
                contacts={@visible}
                selected={@selected}
                selected_bucket={@selected_bucket}
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
                    checklist={@checklist}
                    ticks={@ticks}
                    transcript={@transcript}
                    active_tab={@active_tab}
                    reply_html={@reply_html}
                    reply_nonce={@reply_nonce}
                    note_body={@note_body}
                    error={@error}
                    assignable_users={@assignable_users}
                    current_user={@current_user}
                  />
                <% @visible != [] -> %>
                  <div
                    class="h-full bg-bgSoft border border-border rounded-[11px] flex items-center justify-center text-center px-8"
                    style="box-shadow:var(--shadow-card)"
                  >
                    <div class="text-[14px] text-inkSoft max-w-[300px] leading-[1.55]">
                      {gettext("Select a contact to read the conversation and pick what's next.")}
                    </div>
                  </div>
                <% true -> %>
                  <.empty_bucket bucket={@selected_bucket} />
              <% end %>
            </div>
          </div>
        <% else %>
          <div class="hidden md:flex flex-1 items-center justify-center text-center px-8">
            <div class="text-[14px] text-inkSoft max-w-[320px] leading-[1.55]">
              {gettext("Pick a bucket above. Now is the queue; everything else is bookkeeping.")}
            </div>
          </div>
        <% end %>
      </div>

      <Liid.modal
        :if={@pending_lost}
        id="lost-reason-modal"
        on_cancel="cancel_lost"
        eyebrow={gettext("Lost")}
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
        <ContactForm.form
          id="new-contact-form"
          values={@contact_form}
          error={@create_error}
          email_accounts={@email_accounts}
        />
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

      <Liid.modal
        :if={@editing}
        id="edit-contact-modal"
        on_cancel="cancel_edit"
        eyebrow={gettext("Sales · Funnel")}
        title={gettext("Edit contact")}
        max_width="max-w-[520px]"
      >
        <ContactForm.form
          id="edit-contact-form"
          values={@edit_form}
          error={@edit_error}
          change_event="validate_edit"
          submit_event="update_contact"
          company_editable={@selected != nil and @selected.origin == :manual}
          email_accounts={@email_accounts}
          sender_locked={@selected != nil and @selected.assigned_email_account_id != nil}
          sender_label={sender_label(@selected)}
        />
        <:footer>
          <Liid.btn size={:small} phx-click="cancel_edit">{gettext("Cancel")}</Liid.btn>
          <button
            type="submit"
            form="edit-contact-form"
            class="inline-flex items-center gap-1.5 bg-accent text-white rounded-[8px] px-[16px] py-[8px] text-[12.5px] font-semibold cursor-pointer"
            style="box-shadow:0 1px 2px rgba(59,122,224,.3)"
          >
            {gettext("Save changes")}
          </button>
        </:footer>
      </Liid.modal>
    </Layouts.app>
    """
  end

  # ── Partials ─────────────────────────────────────────────────────────

  attr :contacts, :list, required: true
  attr :selected_bucket, :any, default: nil
  attr :campaign_id, :string, required: true

  # One flush segmented block. `gap-px` over a border-coloured background draws
  # the hairlines between tiles, which works identically for the 2×2 mobile
  # grid and the single desktop row — no per-edge border juggling.
  defp bucket_strip(assigns) do
    ~H"""
    <div
      class="grid grid-cols-2 md:flex gap-px bg-border border border-border rounded-[11px] overflow-hidden"
      style="box-shadow:var(--shadow)"
    >
      <.bucket_tile
        :for={b <- [:now, :later, :won, :lost]}
        bucket={b}
        count={bucket_count(@contacts, b)}
        active?={@selected_bucket == b}
        campaign_id={@campaign_id}
      />
    </div>
    """
  end

  attr :bucket, :atom, required: true
  attr :count, :integer, required: true
  attr :active?, :boolean, default: false
  attr :campaign_id, :string, required: true

  defp bucket_tile(assigns) do
    ~H"""
    <.link
      patch={~p"/campaigns/#{@campaign_id}/sales/#{@bucket}"}
      class={[
        "no-underline text-left p-[13px] cursor-pointer flex flex-col gap-0.5 min-h-[84px] md:flex-1 md:min-w-[112px] transition-colors",
        if(@active?, do: "bg-accentSoft", else: "bg-card hover:bg-bgSoft")
      ]}
    >
      <div class={[
        "flex items-center gap-1.5 text-[11.5px] font-semibold",
        if(@active?, do: "text-accent", else: "text-inkSoft")
      ]}>
        <span class={["w-[7px] h-[7px] rounded-full shrink-0", bucket_dot(@bucket)]} />
        <span class="truncate">{bucket_label(@bucket)}</span>
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
  attr :selected_bucket, :any, default: nil
  attr :campaign_id, :string, required: true

  defp contact_list(assigns) do
    ~H"""
    <div
      class="h-full flex flex-col min-h-0 bg-card border border-border rounded-[11px] overflow-hidden"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="flex-none px-4 py-[13px] border-b border-border flex items-center justify-between">
        <div class="text-[13.5px] font-semibold text-ink">
          <span :if={@selected_bucket} class="text-accent">{bucket_label(@selected_bucket)}</span>
        </div>
        <div class="text-[12px] font-medium text-inkFaint tabular-nums">
          {gettext("%{n} contacts", n: length(@contacts))}
        </div>
      </div>
      <div class="flex-1 overflow-y-auto p-2">
        <%= for c <- @contacts do %>
          <% active? = @selected && @selected.id == c.id %>
          <% {chip_label, chip_class} = row_chip(c) %>
          <.link
            patch={~p"/campaigns/#{@campaign_id}/sales/#{@selected_bucket}/#{c.id}"}
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
            <div class="shrink-0 flex flex-col items-end gap-1">
              <span class={[
                "text-[11px] font-semibold rounded-[6px] px-[7px] py-0.5 tabular-nums",
                chip_class
              ]}>
                {chip_label}
              </span>
              <span :if={c.assigned_to} class="text-[10.5px] text-inkFaint truncate max-w-[110px]">
                {c.assigned_to.email}
              </span>
            </div>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end

  attr :bucket, :atom, required: true

  defp empty_bucket(assigns) do
    ~H"""
    <div
      class="h-full bg-bgSoft border border-border rounded-[11px] flex flex-col items-center justify-center text-center px-8 py-16 gap-4"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="text-[64px] font-bold leading-none text-ink20">0</div>
      <div class="text-[22px] font-semibold tracking-[-0.01em] text-ink">
        {raw(
          gettext("Nothing in <em class=\"text-accent italic font-semibold\">%{bucket}</em>.",
            bucket: bucket_label(@bucket)
          )
        )}
      </div>
      <div class="text-[13px] text-inkSoft max-w-[360px] leading-[1.55]">
        {empty_bucket_hint(@bucket)}
      </div>
    </div>
    """
  end

  defp empty_bucket_hint(:now),
    do: gettext("Inbox zero. Everything is either scheduled or closed.")

  defp empty_bucket_hint(:later),
    do: gettext("Nothing scheduled ahead. Give a contact a next action to park them here.")

  defp empty_bucket_hint(:won), do: gettext("No wins recorded yet.")
  defp empty_bucket_hint(:lost), do: gettext("Nothing written off yet.")

  attr :contact, :map, required: true
  attr :thread, :any, required: true
  attr :timeline, :list, required: true
  attr :checklist, :list, required: true
  attr :ticks, :map, required: true
  attr :transcript, :string, required: true
  attr :active_tab, :atom, required: true
  attr :reply_html, :string, required: true
  attr :reply_nonce, :integer, required: true
  attr :note_body, :string, required: true
  attr :error, :any, default: nil
  attr :assignable_users, :list, required: true
  attr :current_user, :map, required: true

  defp thread_pane(assigns) do
    recipient = (assigns.contact.person && assigns.contact.person.email) || ""
    company = assigns.contact.person && assigns.contact.person.company

    assigns =
      assign(assigns,
        recipient: recipient,
        registry_link: Colt.CompanyRegistry.link(company),
        from_name: FunnelThread.from_display(assigns.contact.assigned_email_account),
        closed?: assigns.contact.outcome != nil,
        next_action_groups: next_action_groups(),
        insert_links: demo_links(assigns.contact)
      )

    ~H"""
    <FunnelThread.thread_pane
      contact={@contact}
      timeline={@timeline}
      transcript={@transcript}
      recipient={@recipient}
      registry_link={@registry_link}
      from_name={@from_name}
      active_tab={@active_tab}
      reply_html={@reply_html}
      reply_nonce={@reply_nonce}
      note_body={@note_body}
      insert_links={@insert_links}
      error={@error}
    >
      <:info_actions>
        <button
          type="button"
          phx-click="open_edit"
          class="inline-flex items-center gap-1.5 rounded-[8px] px-[11px] py-[7px] text-[12.5px] font-semibold cursor-pointer border bg-card border-border text-inkSoft hover:bg-bgSoft"
        >
          {gettext("Edit")}
        </button>
      </:info_actions>

      <:header_actions>
        <div class="relative">
          <button
            type="button"
            phx-click={JS.toggle(to: "#assign-menu-#{@contact.id}")}
            class={[
              "inline-flex items-center gap-1.5 rounded-[8px] px-[11px] py-[7px] text-[12.5px] font-semibold cursor-pointer border",
              if(@contact.assigned_to,
                do: "bg-card border-border text-inkSoft hover:bg-bgSoft",
                else: "bg-accentSoft border-accentRing text-accent"
              )
            ]}
          >
            {claim_label(@contact.assigned_to)}
            <span class="opacity-70 text-[10px]">▾</span>
          </button>
          <div
            id={"assign-menu-#{@contact.id}"}
            class="hidden absolute left-0 top-full mt-1 bg-card border border-border rounded-[8px] z-40 min-w-[200px] py-1"
            style="box-shadow:var(--shadow-card)"
            phx-click-away={JS.hide(to: "#assign-menu-#{@contact.id}")}
          >
            <button
              :for={user <- @assignable_users}
              type="button"
              phx-click={
                JS.push("assign", value: %{user_id: user.id})
                |> JS.hide(to: "#assign-menu-#{@contact.id}")
              }
              class={[
                "flex items-center gap-2 w-full text-left px-3 py-2 text-[12.5px] hover:bg-paperAlt truncate",
                (@contact.assigned_to && @contact.assigned_to.id == user.id &&
                   "text-accent font-semibold") ||
                  "text-inkSoft"
              ]}
            >
              {if user.id == @current_user.id, do: gettext("Me"), else: user.email}
            </button>
          </div>
        </div>
      </:header_actions>

      <:bar_items>
        <.checklist_zone
          :if={@checklist != []}
          checklist={@checklist}
          ticks={@ticks}
          id={@contact.id}
        />
      </:bar_items>

      <:actions>
        <%!-- Outcome is one control, not two buttons: closing is rare next to
             re-dating, and the trigger doubles as the current state. --%>
        <div class="relative">
          <button
            type="button"
            phx-click={JS.toggle(to: "#outcome-menu-#{@contact.id}")}
            class={[
              "inline-flex items-center gap-1.5 rounded-[8px] px-[11px] py-[7px] text-[12.5px] font-semibold cursor-pointer border",
              outcome_button_class(@contact.outcome)
            ]}
          >
            <span
              :if={@contact.outcome}
              class={["w-[7px] h-[7px] rounded-full", outcome_dot(@contact.outcome)]}
            />
            {outcome_button_label(@contact.outcome)}
            <span class="opacity-70 text-[10px]">▾</span>
          </button>
          <div
            id={"outcome-menu-#{@contact.id}"}
            class="hidden absolute right-0 top-full mt-1 bg-card border border-border rounded-[8px] z-40 min-w-[160px] py-1"
            style="box-shadow:var(--shadow-card)"
            phx-click-away={JS.hide(to: "#outcome-menu-#{@contact.id}")}
          >
            <button
              :if={not @closed?}
              phx-click={
                JS.push("set_outcome", value: %{outcome: "won"})
                |> JS.hide(to: "#outcome-menu-#{@contact.id}")
              }
              class="flex items-center gap-2 w-full text-left px-3 py-2 text-[12.5px] text-inkSoft hover:bg-greenSoft hover:text-green"
            >
              <span class="w-[7px] h-[7px] rounded-full bg-green" />{gettext("Won")}
            </button>
            <button
              :if={not @closed?}
              phx-click={
                JS.push("set_outcome", value: %{outcome: "lost"})
                |> JS.hide(to: "#outcome-menu-#{@contact.id}")
              }
              class="flex items-center gap-2 w-full text-left px-3 py-2 text-[12.5px] text-inkSoft hover:bg-redSoft hover:text-red"
            >
              <span class="w-[7px] h-[7px] rounded-full bg-inkFaint" />{gettext("Lost")}
            </button>
            <button
              :if={@closed?}
              phx-click={
                JS.push("set_outcome", value: %{outcome: "reopen"})
                |> JS.hide(to: "#outcome-menu-#{@contact.id}")
              }
              class="flex items-center gap-2 w-full text-left px-3 py-2 text-[12.5px] text-inkSoft hover:bg-paperAlt"
            >
              {gettext("Reopen")}
            </button>
          </div>
        </div>

        <%!-- A closed contact has no next action, so the control goes away
             rather than offering to schedule work on a finished deal. --%>
        <div :if={not @closed?} class="relative">
          <button
            type="button"
            phx-click={JS.toggle(to: "#next-action-menu-#{@contact.id}")}
            class="inline-flex items-center gap-1.5 rounded-[8px] px-[11px] py-[7px] text-[12.5px] font-semibold cursor-pointer border bg-accentSoft border-accentRing text-accent"
          >
            {next_action_button_label(@contact)}
            <span class="opacity-70 text-[10px]">▾</span>
          </button>
          <div
            id={"next-action-menu-#{@contact.id}"}
            class="hidden absolute right-0 top-full mt-1 bg-card border border-border rounded-[8px] z-40 min-w-[230px] py-1"
            style="box-shadow:var(--shadow-card)"
            phx-click-away={JS.hide(to: "#next-action-menu-#{@contact.id}")}
          >
            <div :for={group <- @next_action_groups} class="py-1 border-b border-border">
              <div class="px-3 pb-1 text-[10.5px] font-semibold tracking-[0.08em] uppercase text-inkFaint">
                {group.label}
              </div>
              <button
                :for={item <- group.items}
                phx-click={
                  JS.push("next_action_on", value: %{value: Date.to_iso8601(item.date)})
                  |> JS.hide(to: "#next-action-menu-#{@contact.id}")
                }
                class="flex items-center justify-between gap-4 w-full text-left px-3 py-2 text-[12.5px] text-inkSoft hover:bg-paperAlt"
              >
                <span>{item.label}</span>
                <span class="text-inkFaint tabular-nums">{format_short(item.date)}</span>
              </button>
            </div>

            <div class="py-1 border-b border-border">
              <div class="px-3 pb-1 text-[10.5px] font-semibold tracking-[0.08em] uppercase text-inkFaint">
                {gettext("Custom calendar")}
              </div>
              <form phx-change="next_action_on" class="px-3 pb-1.5">
                <input
                  type="date"
                  name="value"
                  min={Date.to_iso8601(SalesClock.today())}
                  class="w-full px-2 py-1.5 border border-border rounded-[8px] text-[12.5px] bg-card text-ink tabular-nums outline-none focus:border-accentRing"
                />
              </form>
            </div>

            <button
              :if={@contact.next_action_at}
              phx-click={
                JS.push("clear_next_action")
                |> JS.hide(to: "#next-action-menu-#{@contact.id}")
              }
              class="flex items-center gap-2 w-full text-left px-3 py-2 text-[12.5px] text-inkSoft hover:bg-paperAlt"
            >
              {gettext("Clear")}
            </button>
          </div>
        </div>
      </:actions>
    </FunnelThread.thread_pane>
    """
  end

  defp claim_label(nil), do: gettext("Claim")
  defp claim_label(%{email: email}), do: gettext("Assigned: %{email}", email: email)

  defp outcome_button_label(nil), do: gettext("Outcome")
  defp outcome_button_label(:won), do: gettext("Won")
  defp outcome_button_label(:lost), do: gettext("Lost")

  defp outcome_dot(:won), do: "bg-green"
  defp outcome_dot(_), do: "bg-inkFaint"

  defp outcome_button_class(:won), do: "bg-greenSoft border-[#bfe0c4] text-green"
  defp outcome_button_class(:lost), do: "bg-paperAlt border-border text-inkSoft"
  defp outcome_button_class(_), do: "bg-card border-border text-inkSoft hover:bg-bgSoft"

  # "Soon" is the next three individual days; "Next week" is Mon/Tue/Wed of
  # the week after this one, not the next occurrence of those weekdays (so on
  # a Wednesday, "next week" still means next week, not tomorrow).
  defp next_action_groups do
    today = SalesClock.today()
    next_monday = Date.add(today, 8 - Date.day_of_week(today))

    [
      %{
        label: gettext("Soon"),
        items: [
          %{label: gettext("Tomorrow"), date: Date.add(today, 1)},
          %{label: gettext("2 days"), date: Date.add(today, 2)},
          %{label: gettext("3 days"), date: Date.add(today, 3)}
        ]
      },
      %{
        label: gettext("Next week"),
        items: [
          %{label: gettext("Mon"), date: next_monday},
          %{label: gettext("Tue"), date: Date.add(next_monday, 1)},
          %{label: gettext("Wed"), date: Date.add(next_monday, 2)}
        ]
      }
    ]
  end

  defp format_short(%Date{} = date), do: Calendar.strftime(date, "%a %-d %b")

  # The button doubles as the current state, so the date is readable without
  # opening the menu.
  defp next_action_button_label(%{next_action_at: nil}), do: gettext("Next action")

  defp next_action_button_label(%{next_action_at: at}) do
    case SalesClock.days_from_today(at) do
      0 -> gettext("Due today")
      n when n < 0 -> gettext("%{n}d overdue", n: abs(n))
      n -> gettext("in %{n}d", n: n)
    end
  end

  attr :checklist, :list, required: true
  attr :ticks, :map, required: true
  attr :id, :string, required: true

  # The bar shows only what's next; the rest is one click away. Showing the
  # first unticked item answers "what do I do with this person" without
  # spending a whole card on a list that is mostly already done.
  defp checklist_zone(assigns) do
    next_item = Enum.find(assigns.checklist, &(not ticked?(assigns.ticks, &1.id)))

    assigns =
      assign(assigns,
        next_item: next_item,
        done: done_count(assigns.ticks),
        total: length(assigns.checklist),
        menu_id: "checklist-menu-#{assigns.id}"
      )

    ~H"""
    <div class="relative min-w-0">
      <button
        type="button"
        phx-click={JS.toggle(to: "##{@menu_id}")}
        class="inline-flex items-center gap-2 max-w-[240px] rounded-[8px] px-2.5 py-[7px] text-[12.5px] font-medium text-inkSoft hover:bg-paperAlt cursor-pointer"
      >
        <span class={[
          "w-[14px] h-[14px] rounded-[4px] shrink-0 flex items-center justify-center border",
          if(@next_item,
            do: "bg-card border-borderStrong",
            else: "bg-accent border-accent text-white"
          )
        ]}>
          <Liid.icon :if={is_nil(@next_item)} name="check" size={10} class="[stroke-width:2.2]" />
        </span>
        <span class="truncate">
          {if @next_item, do: @next_item.name, else: gettext("All done")}
        </span>
        <span class="shrink-0 text-[11px] text-inkFaint tabular-nums">{@done}/{@total}</span>
        <span class="opacity-50 text-[10px] shrink-0">▾</span>
      </button>

      <div
        id={@menu_id}
        class="hidden absolute left-0 top-full mt-1 z-40 w-[260px] bg-card border border-border rounded-[11px] p-3"
        style="box-shadow:var(--shadow-card)"
        phx-click-away={JS.hide(to: "##{@menu_id}")}
      >
        <div class="flex flex-col gap-2">
          <label
            :for={item <- @checklist}
            class={[
              "flex items-center gap-2.5 text-[13px] text-ink cursor-pointer",
              ticked?(@ticks, item.id) && "opacity-60"
            ]}
          >
            <input
              type="checkbox"
              checked={ticked?(@ticks, item.id)}
              phx-click={JS.push("toggle_checklist", value: %{item: item.id})}
              class="accent-accent w-[15px] h-[15px]"
            />
            <span class={ticked?(@ticks, item.id) && "line-through"}>{item.name}</span>
          </label>
        </div>
      </div>
    </div>
    """
  end

  # One entry per demo cut, each carrying this contact's id as `?c=`. That param
  # is what lets the deck's closing form prefill and mirror the submission back
  # onto this thread as a note — a link pasted without it still works, it just
  # arrives anonymous. Absolute URL: it's going into an email.
  defp demo_links(contact) do
    Enum.map(Slides.variants(), fn variant ->
      %{
        label: Colt.ABTests.label(variant),
        # Not gettext: the deck it links to exists only in Estonian, so a
        # translated anchor would promise a page that isn't there. Every other
        # msgid in this app is English, and an Estonian one would be the odd
        # entry in the .pot.
        #
        # The variant is in the anchor so inserting both links doesn't produce
        # two identical-looking ones in the same email.
        text: "Vaata ülevaadet (#{variant_word(variant)})",
        url: ColtWeb.Endpoint.url() <> ~p"/demo/#{variant}?c=#{contact.id}"
      }
    end)
  end

  defp variant_word("solving_emails"), do: "kirjad kohale"
  defp variant_word(_), do: "mida Liid teeb"
end
