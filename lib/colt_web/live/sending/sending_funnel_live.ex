defmodule ColtWeb.Sending.SendingFunnelLive do
  @moduledoc """
  Sending funnel — left contact list + right thread pane.

  Phase E7 ships the thread pane (read timeline + Trix reply composer +
  notes + Stop sequence + Mark as… override). Stats strip and bucket
  filters land in E8; the placeholder count strip stays in place until
  then.
  """

  use ColtWeb, :live_view

  alias Colt.Resources.{
    Campaign,
    CampaignContact,
    InboundEmail,
    Note,
    OutboundEmail
  }

  alias Colt.Services.Sending.{ManualOverride, SendManualReply, Stats, StopSequence}
  alias Phoenix.LiveView.JS
  alias ColtWeb.Components.Liid
  alias Phoenix.PubSub

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}
  on_mount {ColtWeb.Sending.PanicHook, :default}

  @pubsub Colt.PubSub

  def mount(%{"id" => id} = params, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        if connected?(socket), do: PubSub.subscribe(@pubsub, "campaign:#{campaign.id}")

        contacts = load_contacts(campaign.id, actor)
        selected = pick_contact(contacts, params["contact_id"])
        stats = Stats.for(campaign.id)
        sent_steps = compute_sent_steps(contacts)

        socket =
          socket
          |> assign(
            page_title: "Sending funnel — #{campaign.name}",
            campaign: campaign,
            contacts: contacts,
            selected: selected,
            selected_bucket: :interested,
            stats: stats,
            sent_steps: sent_steps,
            active_tab: :reply,
            reply_html: "",
            reply_nonce: 0,
            note_body: "",
            sending?: false,
            error: nil
          )
          |> load_thread_data()

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  # ── Events ───────────────────────────────────────────────────────────

  def handle_event("select_bucket", %{"bucket" => b}, socket) do
    bucket = String.to_existing_atom(b)
    visible = visible_contacts(socket.assigns.contacts, bucket, socket.assigns.sent_steps)

    socket =
      socket
      |> assign(selected_bucket: bucket)
      |> assign(selected: List.first(visible) || socket.assigns.selected)
      |> load_thread_data()

    {:noreply, socket}
  end

  def handle_event("select_contact", %{"id" => id}, socket) do
    selected = Enum.find(socket.assigns.contacts, &(&1.id == id))

    socket =
      socket
      |> assign(selected: selected, active_tab: :reply, reply_html: "", note_body: "", error: nil)
      |> load_thread_data()

    {:noreply, socket}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in ["reply", "note"] do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  def handle_event("trix_input", %{"value" => v}, socket) do
    {:noreply, assign(socket, reply_html: v)}
  end

  def handle_event("set_note", %{"value" => v}, socket) do
    {:noreply, assign(socket, note_body: v)}
  end

  def handle_event("send_reply", _params, socket) do
    %{selected: contact, reply_html: html, current_user: actor} = socket.assigns

    cond do
      is_nil(contact) ->
        {:noreply, assign(socket, error: "Pick a contact first.")}

      String.trim(strip_html(html)) == "" ->
        {:noreply, assign(socket, error: "Reply body is empty.")}

      true ->
        case SendManualReply.run(contact.thread.id, html, actor: actor) do
          {:ok, _email} ->
            socket =
              socket
              |> assign(
                reply_html: "",
                reply_nonce: socket.assigns.reply_nonce + 1,
                sending?: false,
                error: nil
              )
              |> load_thread_data()
              |> put_flash(:info, "Reply sent.")

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, assign(socket, error: "Send failed: #{inspect(reason)}", sending?: false)}
        end
    end
  end

  def handle_event("save_note", _params, socket) do
    %{selected: contact, note_body: body, current_user: actor} = socket.assigns

    cond do
      is_nil(contact) or String.trim(body) == "" ->
        {:noreply, assign(socket, error: "Note is empty.")}

      true ->
        case Note.create(contact.thread.id, body, actor: actor) do
          {:ok, _} ->
            socket =
              socket
              |> assign(note_body: "", error: nil)
              |> load_thread_data()
              |> put_flash(:info, "Note saved.")

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, assign(socket, error: "Couldn't save note: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("stop_sequence", _params, socket) do
    %{selected: contact, current_user: actor} = socket.assigns

    case StopSequence.run(contact.id, actor: actor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Sequence stopped — contact marked no-reply.")
         |> reload_contacts_and_keep_selected()}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Couldn't stop sequence: #{inspect(reason)}")}
    end
  end

  def handle_event("mark_as", %{"override" => override}, socket) do
    actor = socket.assigns.current_user
    contact = socket.assigns.selected
    atom = String.to_existing_atom(override)

    case ManualOverride.run(contact.id, atom, actor: actor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Marked as #{format_override(atom)}.")
         |> reload_contacts_and_keep_selected()}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Couldn't update: #{inspect(reason)}")}
    end
  end

  # ── PubSub ───────────────────────────────────────────────────────────

  def handle_info({event, _payload}, socket)
      when event in [:email_sent, :next_scheduled, :reply_received, :reply_categorized] do
    {:noreply, reload_contacts_and_keep_selected(socket)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ── Helpers ──────────────────────────────────────────────────────────

  defp load_contacts(campaign_id, actor) do
    case CampaignContact.list_for_campaign(campaign_id,
           load: [:person, :thread],
           actor: actor
         ) do
      {:ok, rows} -> Enum.sort_by(rows, & &1.updated_at, {:desc, DateTime})
      _ -> []
    end
  end

  defp pick_contact([], _), do: nil
  defp pick_contact(contacts, nil), do: List.first(contacts)

  defp pick_contact(contacts, id) do
    Enum.find(contacts, List.first(contacts), &(&1.id == id))
  end

  defp reload_contacts_and_keep_selected(socket) do
    actor = socket.assigns.current_user
    contacts = load_contacts(socket.assigns.campaign.id, actor)
    stats = Stats.for(socket.assigns.campaign.id)
    selected_id = socket.assigns.selected && socket.assigns.selected.id

    selected =
      if selected_id,
        do: Enum.find(contacts, List.first(contacts), &(&1.id == selected_id)),
        else: List.first(contacts)

    socket
    |> assign(
      contacts: contacts,
      selected: selected,
      stats: stats,
      sent_steps: compute_sent_steps(contacts)
    )
    |> load_thread_data()
  end

  # Map contact_id → max sent step_position. Used both for bucket
  # filtering and the contact-list status chip. Cheap enough at v1
  # scale; Stats memoization covers the heavier metric computation.
  defp compute_sent_steps(contacts) do
    Enum.reduce(contacts, %{}, fn c, acc ->
      case c.thread do
        %{id: tid} ->
          case OutboundEmail.list_for_thread(tid, authorize?: false) do
            {:ok, rows} ->
              sent = rows |> Enum.filter(&(&1.status == :sent and &1.step_position != nil))

              case sent do
                [] -> acc
                _ -> Map.put(acc, c.id, sent |> Enum.map(& &1.step_position) |> Enum.max())
              end

            _ ->
              acc
          end

        _ ->
          acc
      end
    end)
  end

  defp visible_contacts(contacts, nil, _sent_map), do: contacts

  defp visible_contacts(contacts, bucket, sent_map) do
    Enum.filter(contacts, fn c ->
      contact_in_bucket?(c, bucket, sent_map)
    end)
  end

  defp contact_in_bucket?(c, :sending, _sent_map),
    do: c.status in [:approved, :sending]

  defp contact_in_bucket?(c, :call_ready, _), do: c.status == :call_ready

  defp contact_in_bucket?(c, :interested, _),
    do: c.status == :replied and c.reply_category == :interested

  defp contact_in_bucket?(c, :not_interested, _) do
    c.status == :no_reply or
      (c.status == :replied and c.reply_category in [:not_interested, :ooo, :other])
  end

  defp contact_in_bucket?(c, :failed, _), do: c.status == :failed
  defp contact_in_bucket?(c, :bounced, _), do: c.status == :bounced
  defp contact_in_bucket?(_, _, _), do: true

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

      timeline = build_timeline(outbound, inbound, notes)
      assign(socket, timeline: timeline, thread: thread)
    else
      assign(socket, timeline: [], thread: nil)
    end
  end

  defp build_timeline(outbound, inbound, notes) do
    out_items =
      outbound
      |> Enum.reject(&(&1.status == :skipped))
      |> Enum.map(fn e ->
        %{
          kind: if(e.is_manual_reply, do: :manual_outbound, else: :outbound),
          at: e.sent_at || e.scheduled_at || e.inserted_at,
          email: e
        }
      end)

    in_items = Enum.map(inbound, fn e -> %{kind: :inbound, at: e.received_at, email: e} end)
    note_items = Enum.map(notes, fn n -> %{kind: :note, at: n.inserted_at, note: n} end)

    (out_items ++ in_items ++ note_items)
    |> Enum.sort_by(& &1.at, {:asc, DateTime})
  end

  defp strip_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&nbsp;", " ")
    |> String.trim()
  end

  defp strip_html(_), do: ""

  defp format_override(:interested), do: "interested"
  defp format_override(:not_interested), do: "not interested"
  defp format_override(:ooo), do: "out of office"
  defp format_override(:call_ready), do: "call ready"
  defp format_override(:no_reply), do: "no reply"

  defp status_label(%{status: status, reply_category: cat}) do
    {label, tone} = base_status_label(status)

    case cat do
      nil -> {label, tone}
      _ -> {label <> " · " <> category_label(cat), tone}
    end
  end

  defp base_status_label(:pending_approval), do: {"pending", "ink55"}
  defp base_status_label(:approved), do: {"approved", "ink70"}
  defp base_status_label(:sending), do: {"sending", "ink70"}
  defp base_status_label(:replied), do: {"replied", "accent"}
  defp base_status_label(:call_ready), do: {"call ready", "accent"}
  defp base_status_label(:no_reply), do: {"no reply", "ink40"}
  defp base_status_label(:bounced), do: {"bounced", "warn"}
  defp base_status_label(:failed), do: {"failed", "fail"}

  defp category_label(:interested), do: "interested"
  defp category_label(:not_interested), do: "not interested"
  defp category_label(:ooo), do: "ooo"
  defp category_label(:other), do: "other"

  defp terminal?(s), do: s in [:replied, :no_reply, :bounced, :failed, :call_ready]

  # ── Render ───────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:sending_funnel}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="flex flex-col h-[calc(100vh-120px)]">
        <.bounce_banner
          :if={@campaign.panic_switch_on and @stats.bounce_rate >= 5.0}
          rate={@stats.bounce_rate}
        />
        <div class="px-7 pt-6 pb-4">
          <Liid.headline kicker="Sending · Funnel">
            Where the <em class="text-accent">conversation</em> is going.
          </Liid.headline>
        </div>

        <div class="px-7 pb-4">
          <.bucket_strip stats={@stats} selected_bucket={@selected_bucket} />
        </div>

        <div class="grid grid-cols-[360px_1fr] flex-1 min-h-0 border-t border-rule">
          <.contact_list
            contacts={visible_contacts(@contacts, @selected_bucket, @sent_steps)}
            selected={@selected}
            selected_bucket={@selected_bucket}
          />
          <%= if @selected do %>
            <.thread_pane
              contact={@selected}
              thread={@thread}
              timeline={@timeline}
              active_tab={@active_tab}
              reply_html={@reply_html}
              reply_nonce={@reply_nonce}
              note_body={@note_body}
              sending?={@sending?}
              error={@error}
              campaign_id={@campaign.id}
            />
          <% else %>
            <div class="flex items-center justify-center text-ink40 font-mono text-[11px]">
              No contacts to show yet.
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Partials ─────────────────────────────────────────────────────────

  attr :rate, :float, required: true

  defp bounce_banner(assigns) do
    ~H"""
    <div
      class="px-6 py-2.5 text-paper font-mono text-[11px] tracking-[0.06em] uppercase flex items-center gap-3"
      style="background: var(--fail);"
    >
      <span class="inline-block w-[7px] h-[7px] rounded-full bg-paper animate-[liid-pulse_1.4s_ease-in-out_infinite]" />
      <span class="font-semibold tracking-[0.12em]">Campaign auto-paused</span>
      <span class="opacity-90 normal-case tracking-normal">
        Bounce rate {Float.round(@rate, 1)}% · above the 5% threshold. Investigate before resuming.
      </span>
    </div>
    """
  end

  attr :stats, :map, required: true
  attr :selected_bucket, :any, default: nil

  defp bucket_strip(assigns) do
    b = assigns.stats.buckets

    sending =
      Map.get(b, :pending_send, 0) +
        Enum.reduce(b, 0, fn {k, n}, acc ->
          case Atom.to_string(k) do
            "step_" <> _ -> acc + n
            _ -> acc
          end
        end)

    not_interested =
      Map.get(b, :replied_not_interested, 0) + Map.get(b, :replied_ooo, 0) +
        Map.get(b, :replied_other, 0) + Map.get(b, :no_reply, 0)

    tiles = [
      %{
        k: :sending,
        label: "Sending",
        big: sending,
        unit: "contacts",
        sub: "#{assigns.stats.total_sent} emails sent",
        pulse: true
      },
      %{
        k: :call_ready,
        label: "Call ready",
        big: Map.get(b, :call_ready, 0),
        unit: "contacts",
        sub: "",
        tone: :accent
      },
      %{
        k: :interested,
        label: "Interested",
        big: Map.get(b, :replied_interested, 0),
        unit: "contacts",
        sub: "#{assigns.stats.interest_rate}% interest",
        tone: :accent
      },
      %{
        k: :not_interested,
        label: "Not interested",
        big: not_interested,
        unit: "contacts",
        sub: "#{assigns.stats.reply_rate}% reply rate"
      },
      %{
        k: :failed,
        label: "Failed",
        big: Map.get(b, :failed, 0),
        unit: "contacts",
        sub: "#{failure_rate(b, assigns.stats.total_contacts)}% failure rate",
        tone: :fail
      },
      %{
        k: :bounced,
        label: "Bounced",
        big: assigns.stats.total_bounced,
        unit: "contacts",
        sub: "#{Float.round(assigns.stats.bounce_rate, 1)}% bounce rate",
        tone: bounce_tone(assigns.stats.bounce_rate)
      }
    ]

    assigns = assign(assigns, tiles: tiles)

    ~H"""
    <div class="grid grid-cols-6 border border-rule rounded-[2px] bg-paper">
      <%= for {t, i} <- Enum.with_index(@tiles) do %>
        <% active? = @selected_bucket == t.k %>
        <button
          phx-click="select_bucket"
          phx-value-bucket={t.k}
          class={[
            "text-left p-4 cursor-pointer relative",
            i < length(@tiles) - 1 && "border-r border-rule",
            active? && "bg-paperAlt"
          ]}
        >
          <span
            :if={active?}
            class="absolute left-0 right-0 bottom-0 h-[2px]"
            style="background: var(--accent);"
          />
          <div class="flex items-center gap-2 mb-1.5 font-mono text-[10px] uppercase tracking-[0.12em] text-ink55">
            <span
              :if={Map.get(t, :pulse)}
              class="w-[5px] h-[5px] rounded-full"
              style={"background: #{tone_color(Map.get(t, :tone, :ink))}; animation: liid-pulse 1.4s ease-in-out infinite;"}
            />
            {t.label}
          </div>
          <div class="flex items-baseline gap-1.5">
            <span
              class="font-serif text-[36px] leading-none tabular-nums"
              style={"color: #{tone_color(Map.get(t, :tone, :ink))};"}
            >
              {t.big}
            </span>
            <span class="font-mono text-[11px] text-ink55">{t.unit}</span>
          </div>
          <div class="mt-2.5 pt-2 border-t border-rule font-mono text-[10px] text-ink55">
            {t.sub}
          </div>
        </button>
      <% end %>
    </div>
    """
  end

  defp failure_rate(_, 0), do: 0.0

  defp failure_rate(buckets, total),
    do: Float.round(Map.get(buckets, :failed, 0) / total * 100, 1)

  defp bounce_tone(rate) when is_number(rate) and rate >= 5.0, do: :fail
  defp bounce_tone(rate) when is_number(rate) and rate >= 3.0, do: :warn
  defp bounce_tone(_), do: :default

  defp tone_color(:accent), do: "var(--accent)"
  defp tone_color(:fail), do: "var(--fail)"
  defp tone_color(:warn), do: "var(--warn)"
  defp tone_color(_), do: "var(--ink)"

  attr :contacts, :list, required: true
  attr :selected, :map, default: nil
  attr :selected_bucket, :any, default: nil

  defp contact_list(assigns) do
    ~H"""
    <div class="border-r border-rule overflow-y-auto bg-paper">
      <div class="px-4 py-3 border-b border-rule font-mono text-[10px] tracking-[0.04em] text-ink55 sticky top-0 bg-paper z-10">
        {length(@contacts)} contacts
      </div>
      <%= for c <- @contacts do %>
        <% active? = @selected && @selected.id == c.id %>
        <% {label, tone} = status_label(c) %>
        <button
          phx-click="select_contact"
          phx-value-id={c.id}
          class={[
            "w-full text-left px-4 py-3 border-b border-rule relative cursor-pointer block",
            if(active?, do: "bg-paperAlt", else: "bg-paper hover:bg-paperAlt")
          ]}
        >
          <span
            :if={active?}
            class="absolute left-0 top-1 bottom-1 w-[2px]"
            style="background: var(--accent);"
          />
          <div class="flex justify-between items-baseline mb-1">
            <span class={["text-[13px] text-ink truncate", active? && "font-semibold"]}>
              {(c.person && c.person.name) || "—"}
            </span>
            <span class={"font-mono text-[10px] text-#{tone}"}>{label}</span>
          </div>
          <div class="flex justify-between text-[11px] text-ink55">
            <span class="truncate">{(c.person && c.person.title) || ""}</span>
          </div>
        </button>
      <% end %>
    </div>
    """
  end

  attr :contact, :map, required: true
  attr :thread, :any, required: true
  attr :timeline, :list, required: true
  attr :active_tab, :atom, required: true
  attr :reply_html, :string, required: true
  attr :reply_nonce, :integer, required: true
  attr :note_body, :string, required: true
  attr :sending?, :boolean, required: true
  attr :recipient, :string, default: ""
  attr :error, :any, default: nil
  attr :campaign_id, :string, required: true

  defp thread_pane(assigns) do
    {status_text, status_tone} = status_label(assigns.contact)
    recipient = (assigns.contact.person && assigns.contact.person.email) || ""

    assigns =
      assign(assigns,
        status_text: status_text,
        status_tone: status_tone,
        recipient: recipient,
        overrides: ManualOverride.overrides()
      )

    ~H"""
    <div class="flex flex-col min-h-0 bg-paper">
      <div class="px-7 py-4 border-b border-rule flex items-start gap-4">
        <div class="flex-1 min-w-0">
          <div class="flex items-baseline gap-3 flex-wrap">
            <span class="font-serif text-[24px] text-ink leading-none">
              {(@contact.person && @contact.person.name) || "—"}
            </span>
            <span class="text-[12px] text-ink55">
              {(@contact.person && @contact.person.title) || ""}
            </span>
            <span class="font-mono text-[10px] text-ink40">{@recipient}</span>
          </div>
        </div>

        <div class="flex items-center gap-2 relative">
          <button
            type="button"
            phx-click={JS.toggle(to: "#status-menu-#{@contact.id}")}
            class={"font-mono text-[10px] uppercase tracking-[0.08em] px-2 py-1 border border-rule rounded-[2px] cursor-pointer hover:bg-paperAlt text-#{@status_tone}"}
          >
            ● {@status_text} ▾
          </button>
          <div
            id={"status-menu-#{@contact.id}"}
            class="hidden absolute right-0 top-full mt-1 bg-paper border border-rule rounded-[2px] z-20 min-w-[180px] shadow-sm"
            phx-click-away={JS.hide(to: "#status-menu-#{@contact.id}")}
          >
            <%= for o <- @overrides do %>
              <button
                phx-click={
                  JS.push("mark_as", value: %{override: o})
                  |> JS.hide(to: "#status-menu-#{@contact.id}")
                }
                class="block w-full text-left px-3 py-2 font-mono text-[11px] hover:bg-paperAlt"
              >
                {format_override(o)}
              </button>
            <% end %>
          </div>

          <Liid.btn
            size={:small}
            mono
            phx-click="stop_sequence"
            disabled={terminal?(@contact.status)}
          >
            Stop sequence
          </Liid.btn>
        </div>
      </div>

      <div class="flex-1 overflow-y-auto px-7 py-6">
        <%= if @timeline == [] do %>
          <div class="text-ink40 font-mono text-[11px]">
            No messages yet. The first step will appear here once it sends.
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
          sending?={@sending?}
          recipient={@recipient}
          error={@error}
        />
      </div>
    </div>
    """
  end

  attr :item, :map, required: true

  defp timeline_item(%{item: %{kind: :note}} = assigns) do
    ~H"""
    <div
      class="my-4 max-w-[640px] p-4 rounded-[2px] border"
      style="background:#fef4a8;border-color:rgba(220,190,80,0.4);"
    >
      <div
        class="flex justify-between font-mono text-[10px] uppercase mb-1.5"
        style="color:rgba(90,74,42,0.7);"
      >
        <span>Note</span>
        <span>{Calendar.strftime(@item.at, "%b %d · %H:%M")}</span>
      </div>
      <div class="font-serif italic text-[15px] leading-[1.5]" style="color:#5a4a2a;">
        {@item.note.body}
      </div>
    </div>
    """
  end

  defp timeline_item(%{item: %{kind: kind}} = assigns)
       when kind in [:outbound, :manual_outbound, :inbound] do
    outbound? = kind in [:outbound, :manual_outbound]
    inbound? = kind == :inbound
    manual? = kind == :manual_outbound

    chip =
      cond do
        manual? -> "reply (you)"
        outbound? -> "step #{(assigns.item.email.step_position || 0) + 1}"
        true -> "reply"
      end

    body =
      if inbound?,
        do: assigns.item.email.body,
        else: assigns.item.email.user_body || assigns.item.email.ai_body || ""

    subject =
      if inbound? do
        assigns.item.email.subject
      else
        assigns.item.email.user_subject || assigns.item.email.ai_subject
      end

    sender = if inbound?, do: assigns.item.email.from_address, else: "you"

    assigns =
      assign(assigns,
        outbound?: outbound?,
        inbound?: inbound?,
        chip: chip,
        body: body,
        subject: subject,
        sender: sender
      )

    ~H"""
    <div class={["my-4 max-w-[720px]", if(@outbound?, do: "mr-auto", else: "ml-auto")]}>
      <div class="flex items-center gap-2 mb-1.5 font-mono text-[10px] text-ink55">
        <span
          class={[
            "inline-flex items-center px-2 py-0.5 rounded-[2px] uppercase font-semibold",
            @outbound? && "bg-ink text-paper"
          ]}
          style={
            unless @outbound?,
              do:
                "background:color-mix(in oklch, var(--accent) 12%, transparent);color:var(--accent);"
          }
        >
          {@chip}
        </span>
        <span>{@sender}</span>
        <span>·</span>
        <span>{Calendar.strftime(@item.at, "%b %d · %H:%M")}</span>
        <span :if={@outbound? and @item.email.status == :scheduled} class="text-ink40">
          · scheduled
        </span>
        <span :if={@outbound? and @item.email.status == :bounced} class="text-warn">· bounced</span>
        <span :if={@outbound? and @item.email.status == :failed} class="text-fail">· failed</span>
        <span :if={@outbound? and @item.email.status == :skipped} class="text-ink40">· skipped</span>
      </div>
      <div
        class={[
          "p-4 border border-rule rounded-[2px]",
          if(@outbound?, do: "bg-paper", else: "bg-paperAlt")
        ]}
        style={if(@inbound?, do: "border-left:2px solid var(--accent);")}
      >
        <div :if={@subject} class="text-[13px] font-semibold text-ink mb-2">{@subject}</div>
        <div class="text-[13px] leading-[1.6] text-ink70 whitespace-pre-wrap">
          {body_text(@body)}
        </div>
      </div>
    </div>
    """
  end

  # Inbound + manual-reply bodies arrive as HTML; outbound AI drafts are
  # plain text. Strip tags for a uniform read-only timeline display.
  defp body_text(text) when is_binary(text) do
    text
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<[^>]+>/, "")
  end

  defp body_text(_), do: ""

  attr :active_tab, :atom, required: true
  attr :reply_html, :string, required: true
  attr :reply_nonce, :integer, required: true
  attr :note_body, :string, required: true
  attr :sending?, :boolean, required: true
  attr :recipient, :string, required: true
  attr :error, :any, default: nil

  defp composer(assigns) do
    ~H"""
    <div class="mt-8 max-w-[720px] border border-ink20 rounded-[2px] bg-paper">
      <div class="flex items-center border-b border-rule px-6">
        <button
          phx-click="switch_tab"
          phx-value-tab="reply"
          class={[
            "px-4 py-3 text-[12px]",
            if(@active_tab == :reply,
              do: "font-semibold text-ink border-b-2 border-ink -mb-px",
              else: "text-ink55"
            )
          ]}
        >
          Reply
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="note"
          class={[
            "px-4 py-3 text-[12px]",
            if(@active_tab == :note,
              do: "font-semibold text-ink border-b-2 border-ink -mb-px",
              else: "text-ink55"
            )
          ]}
        >
          Note
        </button>
        <span class="flex-1" />
        <span :if={@active_tab == :reply} class="font-mono text-[10px] text-ink40 truncate">
          To: {@recipient}
        </span>
      </div>

      <div :if={@error} class="px-6 pt-3 text-[12px] text-fail">{@error}</div>

      <div
        :if={@active_tab == :reply}
        class="px-6 py-4"
        id={"trix-wrap-#{@reply_nonce}"}
        phx-hook="TrixEditor"
        phx-update="ignore"
      >
        <input id={"trix-content-#{@reply_nonce}"} type="hidden" value={@reply_html} />
        <trix-editor
          input={"trix-content-#{@reply_nonce}"}
          class="trix-content"
          style="min-height:120px;"
        >
        </trix-editor>
        <div class="mt-3 flex justify-end">
          <Liid.btn
            variant={:primary}
            size={:small}
            mono
            phx-click="send_reply"
            disabled={@sending?}
          >
            <Liid.icon name="arrow" size={11} /> Send reply
          </Liid.btn>
        </div>
      </div>

      <div :if={@active_tab == :note} class="px-6 py-4">
        <form phx-change="set_note">
          <textarea
            name="value"
            rows="4"
            phx-debounce="300"
            placeholder="Internal note — not sent to recipient."
            class="w-full px-3 py-2 border border-ink20 rounded-[2px] text-[13px] outline-none resize-none"
          >{@note_body}</textarea>
        </form>
        <div class="mt-3 flex justify-end">
          <Liid.btn variant={:primary} size={:small} mono phx-click="save_note">
            Save note
          </Liid.btn>
        </div>
      </div>
    </div>
    """
  end
end
