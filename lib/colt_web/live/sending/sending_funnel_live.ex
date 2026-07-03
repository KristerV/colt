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
    OutboundEmail,
    Sequence
  }

  alias Colt.Services.Sending.{ManualOverride, SendManualReply, Stats, StopSequence}
  alias Phoenix.LiveView.JS
  alias ColtWeb.Components.Liid
  alias Phoenix.PubSub

  on_mount {ColtWeb.LiveUserAuth, :live_plan_required}
  on_mount {ColtWeb.Sending.PanicHook, :default}
  on_mount {ColtWeb.Sending.MarkInitializedHook, :default}

  @pubsub Colt.PubSub

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        if connected?(socket), do: PubSub.subscribe(@pubsub, "campaign:#{campaign.id}")

        contacts = load_contacts(campaign.id, actor)
        sent_steps = compute_sent_steps(contacts)
        stats = Stats.for(campaign.id)
        total_steps = count_email_steps(campaign.id, actor)

        socket =
          socket
          |> assign(
            page_title: gettext("Sending funnel — %{name}", name: campaign.name),
            campaign: campaign,
            contacts: contacts,
            selected: nil,
            selected_bucket: nil,
            stats: stats,
            sent_steps: sent_steps,
            total_steps: total_steps,
            active_tab: :reply,
            reply_html: "",
            reply_nonce: 0,
            note_body: "",
            sending?: false,
            error: nil,
            timeline: [],
            thread: nil
          )

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  # Selection lives in the URL: /sending-funnel/:bucket/:contact_id drives the
  # bucket + open contact, so the browser back button walks the drill-down and
  # every level is deep-linkable. Mobile shows one level at a time; desktop
  # renders the full two-pane (see render/1).
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
        active_tab: :reply,
        reply_html: "",
        note_body: "",
        error: nil
      )
      |> load_thread_data()

    {:noreply, socket}
  end

  defp parse_bucket(nil), do: nil

  defp parse_bucket(b) when is_binary(b) do
    String.to_existing_atom(b)
  rescue
    ArgumentError -> nil
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
            socket =
              socket
              |> assign(
                reply_html: "",
                reply_nonce: socket.assigns.reply_nonce + 1,
                sending?: false,
                error: nil
              )
              |> load_thread_data()
              |> put_flash(:info, gettext("Reply sent."))

            {:noreply, socket}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               error: gettext("Send failed: %{reason}", reason: inspect(reason)),
               sending?: false
             )}
        end
    end
  end

  def handle_event("save_note", _params, socket) do
    %{selected: contact, note_body: body, current_user: actor} = socket.assigns

    cond do
      is_nil(contact) or String.trim(body) == "" ->
        {:noreply, assign(socket, error: gettext("Note is empty."))}

      true ->
        case Note.create(contact.thread.id, body, actor: actor) do
          {:ok, _} ->
            socket =
              socket
              |> assign(note_body: "", error: nil)
              |> load_thread_data()
              |> put_flash(:info, gettext("Note saved."))

            {:noreply, socket}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               error: gettext("Couldn't save note: %{reason}", reason: inspect(reason))
             )}
        end
    end
  end

  def handle_event("stop_sequence", _params, socket) do
    %{selected: contact, current_user: actor} = socket.assigns

    case StopSequence.run(contact.id, actor: actor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Sequence stopped — contact marked no-reply."))
         |> reload_contacts_and_keep_selected()}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           error: gettext("Couldn't stop sequence: %{reason}", reason: inspect(reason))
         )}
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
         |> put_flash(:info, gettext("Marked as %{label}.", label: format_override(atom)))
         |> reload_contacts_and_keep_selected()}

      {:error, reason} ->
        {:noreply,
         assign(socket, error: gettext("Couldn't update: %{reason}", reason: inspect(reason)))}
    end
  end

  # ── PubSub ───────────────────────────────────────────────────────────

  # Broadcasts carry varying arity ({:email_sent, email_id, contact_id, step}
  # is a 4-tuple, {:reply_categorized, contact_id, category} a 3-tuple), so
  # match on the leading event atom rather than a fixed tuple shape.
  def handle_info(msg, socket)
      when is_tuple(msg) and
             elem(msg, 0) in [
               :email_sent,
               :email_failed,
               :email_skipped,
               :next_scheduled,
               :inbound_received,
               :reply_categorized,
               :sequence_halted
             ] do
    {:noreply, reload_contacts_and_keep_selected(socket)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ── Helpers ──────────────────────────────────────────────────────────

  defp load_contacts(campaign_id, actor) do
    case CampaignContact.list_for_campaign(campaign_id,
           load: [:thread, :assigned_email_account, person: :company],
           actor: actor
         ) do
      {:ok, rows} -> Enum.sort_by(rows, & &1.updated_at, {:desc, DateTime})
      _ -> []
    end
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

  # Map contact_id → count of distinct sequence steps actually sent.
  # Drives the "n/total" progress badge in the contact list. Cheap enough
  # at v1 scale; Stats memoization covers the heavier metric computation.
  defp compute_sent_steps(contacts) do
    Enum.reduce(contacts, %{}, fn c, acc ->
      case c.thread do
        %{id: tid} ->
          case OutboundEmail.list_for_thread(tid, authorize?: false) do
            {:ok, rows} ->
              count =
                rows
                |> Enum.filter(&(&1.status == :sent and &1.step_position != nil))
                |> Enum.map(& &1.step_position)
                |> Enum.uniq()
                |> length()

              if count > 0, do: Map.put(acc, c.id, count), else: acc

            _ ->
              acc
          end

        _ ->
          acc
      end
    end)
  end

  # Total number of email steps in the campaign's sequence — the
  # denominator of the "n/total" contact-list badge.
  defp count_email_steps(campaign_id, actor) do
    case Sequence.get_for_campaign(campaign_id, load: [:sequence_steps], actor: actor) do
      {:ok, %{sequence_steps: steps}} -> Enum.count(steps, &(&1.kind == :email))
      _ -> 0
    end
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

  # A sequence step that's neither sent nor scheduled has no real moment
  # in time — its inserted_at is just when the draft row was written, which
  # scrambles the timeline (step 3 drafted before step 1 ⇒ step 3 jumps
  # ahead). Pin those to the very end, in step order, with no display date.
  @unscheduled_sentinel ~U[9999-01-01 00:00:00.000000Z]

  defp build_timeline(outbound, inbound, notes) do
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

    (out_items ++ in_items ++ note_items)
    |> Enum.sort_by(&{DateTime.to_unix(&1.sort_at, :microsecond), &1.sort_pos})
  end

  # Real clock for an outbound row: when it was sent, else when it's
  # scheduled to send. A bare draft (drafted/approved) returns nil.
  defp outbound_at(%{sent_at: at}) when not is_nil(at), do: at
  defp outbound_at(%{scheduled_at: at}) when not is_nil(at), do: at
  defp outbound_at(_), do: nil

  # Human label for the assigned sending inbox — display name if set, else the
  # email's local-part humanized (mirrors the writer's own fallback). nil when
  # no inbox is assigned yet (e.g. a contact still pending in Writing).
  defp from_display(%{} = account),
    do: display_name(account) || local_part(Map.get(account, :address))

  defp from_display(_), do: nil

  defp display_name(%{display_name: sig}) when is_binary(sig) do
    sig |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.find(&(&1 != ""))
  end

  defp display_name(_), do: nil

  defp local_part(address) when is_binary(address) do
    address
    |> String.split("@")
    |> List.first()
    |> String.split(~r/[._]/)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp local_part(_), do: nil

  # Up-to-two-letter initials from a person's name for the list/thread avatar.
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

  defp format_override(:interested), do: gettext("interested")
  defp format_override(:not_interested), do: gettext("not interested")
  defp format_override(:ooo), do: gettext("out of office")
  defp format_override(:call_ready), do: gettext("call ready")
  defp format_override(:no_reply), do: gettext("no reply")

  defp status_label(%{status: status, reply_category: cat}) do
    {label, tone} = base_status_label(status)

    case cat do
      nil -> {label, tone}
      _ -> {label <> " · " <> category_label(cat), tone}
    end
  end

  defp base_status_label(:pending_approval), do: {gettext("pending"), "ink55"}
  defp base_status_label(:approved), do: {gettext("approved"), "ink70"}
  defp base_status_label(:sending), do: {gettext("sending"), "ink70"}
  defp base_status_label(:replied), do: {gettext("replied"), "accent"}
  defp base_status_label(:call_ready), do: {gettext("call ready"), "accent"}
  defp base_status_label(:no_reply), do: {gettext("no reply"), "ink40"}
  defp base_status_label(:bounced), do: {gettext("bounced"), "warn"}
  defp base_status_label(:failed), do: {gettext("failed"), "fail"}

  defp category_label(:interested), do: gettext("interested")
  defp category_label(:not_interested), do: gettext("not interested")
  defp category_label(:ooo), do: gettext("ooo")
  defp category_label(:other), do: gettext("other")

  defp terminal?(s), do: s in [:replied, :no_reply, :bounced, :failed, :call_ready]

  # Soft pill styling for the thread-header status control, keyed by the tone
  # returned from status_label/1.
  defp status_ctl_class("accent"),
    do: "bg-accentSoft border-accentRing text-accent"

  defp status_ctl_class("warn"), do: "bg-amberSoft border-amber/30 text-amber"
  defp status_ctl_class("fail"), do: "bg-redSoft border-red/30 text-red"
  defp status_ctl_class(_), do: "bg-paperAlt border-border text-inkSoft"

  defp status_dot_class("accent"), do: "bg-accent"
  defp status_dot_class("warn"), do: "bg-amber"
  defp status_dot_class("fail"), do: "bg-red"
  defp status_dot_class(_), do: "bg-inkFaint"

  # ── Render ───────────────────────────────────────────────────────────

  def render(assigns) do
    level =
      cond do
        assigns.selected -> :thread
        assigns.selected_bucket -> :list
        true -> :buckets
      end

    visible =
      if assigns.selected_bucket,
        do: visible_contacts(assigns.contacts, assigns.selected_bucket, assigns.sent_steps),
        else: []

    assigns =
      assign(assigns,
        level: level,
        bucket_label: bucket_label(assigns.selected_bucket),
        visible: visible
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:sending_funnel}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="flex flex-col md:h-screen md:-mx-14 md:-my-10">
        <.bounce_banner
          :if={@campaign.panic_switch_on and @stats.bounce_rate >= 5.0}
          rate={@stats.bounce_rate}
        />

        <%!-- Mobile back-bar: appears once you drill into a category/contact --%>
        <div :if={@level != :buckets} class="md:hidden px-2 pt-2 pb-1">
          <.link
            patch={
              if @level == :thread,
                do: ~p"/campaigns/#{@campaign.id}/sending-funnel/#{to_string(@selected_bucket)}",
                else: ~p"/campaigns/#{@campaign.id}/sending-funnel"
            }
            class="inline-flex items-center gap-2 py-2.5 px-2 text-[15px] font-medium text-inkSoft active:text-ink hover:text-ink no-underline"
          >
            <span class="text-[30px] leading-none -mt-0.5">‹</span>
            <span class="capitalize">
              {if @level == :thread,
                do: gettext("Back to %{bucket}", bucket: @bucket_label),
                else: gettext("All categories")}
            </span>
          </.link>
        </div>

        <%!-- Top band (headline + categories + tracking): always on desktop, mobile only at top level --%>
        <div class={[
          "px-4 md:px-7 pt-5 md:pt-6 pb-4 flex-none",
          (@level == :buckets && "block") || "hidden md:block"
        ]}>
          <Liid.headline kicker={gettext("Sending · Funnel")}>
            {raw(gettext("Where the <em class=\"text-accent\">conversation</em> is going."))}
          </Liid.headline>

          <div class="mt-4">
            <.bucket_strip
              stats={@stats}
              selected_bucket={@selected_bucket}
              campaign_id={@campaign.id}
            />
          </div>

          <.tracking_strip
            :if={@campaign.tracking_opens? or @campaign.tracking_clicks?}
            campaign={@campaign}
            stats={@stats}
          />
        </div>

        <%= if @selected_bucket do %>
          <div class="grid grid-cols-1 md:grid-cols-[360px_1fr] flex-1 min-h-0 gap-4 px-0 md:px-7 pb-4 md:pb-6">
            <div class={["min-h-0", (@level == :list && "block") || "hidden", "md:block"]}>
              <.contact_list
                contacts={@visible}
                selected={@selected}
                selected_bucket={@selected_bucket}
                sent_steps={@sent_steps}
                total_steps={@total_steps}
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
                    active_tab={@active_tab}
                    reply_html={@reply_html}
                    reply_nonce={@reply_nonce}
                    note_body={@note_body}
                    sending?={@sending?}
                    error={@error}
                    campaign_id={@campaign.id}
                  />
                <% @visible != [] -> %>
                  <div
                    class="h-full bg-bgSoft border border-border rounded-[11px] flex items-center justify-center text-center px-8"
                    style="box-shadow:var(--shadow-card)"
                  >
                    <div class="text-[14px] text-inkSoft max-w-[300px] leading-[1.55]">
                      {gettext("Select a contact to read the conversation.")}
                    </div>
                  </div>
                <% true -> %>
                  <.empty_pane bucket={@selected_bucket} campaign_id={@campaign.id} />
              <% end %>
            </div>
          </div>
        <% else %>
          <div class="hidden md:flex flex-1 items-center justify-center text-center px-8">
            <div class="text-[14px] text-inkSoft max-w-[320px] leading-[1.55]">
              {gettext("Pick a category above to dive into its contacts.")}
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp bucket_label(nil), do: gettext("this category")
  defp bucket_label(b), do: b |> Atom.to_string() |> String.replace("_", " ")

  # ── Partials ─────────────────────────────────────────────────────────

  attr :rate, :float, required: true

  defp bounce_banner(assigns) do
    ~H"""
    <div class="mx-7 mt-6 bg-redSoft border border-red/30 rounded-[11px] px-5 py-3 flex items-center gap-3">
      <span class="inline-block w-[7px] h-[7px] rounded-full bg-red animate-[liid-pulse_1.4s_ease-in-out_infinite]" />
      <span class="text-[12.5px] font-semibold text-red">{gettext("Campaign auto-paused")}</span>
      <span class="text-[12.5px] text-red/90">
        {gettext(
          "Bounce rate %{rate}% · above the 5% threshold. Investigate before resuming.",
          rate: @rate
        )}
      </span>
    </div>
    """
  end

  attr :stats, :map, required: true
  attr :selected_bucket, :any, default: nil
  attr :campaign_id, :string, required: true

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
        label: gettext("Sending"),
        big: sending,
        unit: gettext("contacts"),
        sub: gettext("%{n} emails sent", n: assigns.stats.total_sent),
        pulse: true
      },
      %{
        k: :call_ready,
        label: gettext("Call ready"),
        big: Map.get(b, :call_ready, 0),
        unit: gettext("contacts"),
        sub: "",
        tone: :accent
      },
      %{
        k: :interested,
        label: gettext("Interested"),
        big: Map.get(b, :replied_interested, 0),
        unit: gettext("contacts"),
        sub: gettext("%{rate}% interest", rate: assigns.stats.interest_rate),
        tone: :accent
      },
      %{
        k: :not_interested,
        label: gettext("Not interested"),
        big: not_interested,
        unit: gettext("contacts"),
        sub: gettext("%{rate}% reply rate", rate: assigns.stats.reply_rate)
      },
      %{
        k: :failed,
        label: gettext("Failed"),
        big: Map.get(b, :failed, 0),
        unit: gettext("contacts"),
        sub:
          gettext("%{rate}% failure rate",
            rate: failure_rate(b, assigns.stats.total_contacts)
          ),
        tone: :fail
      },
      %{
        k: :bounced,
        label: gettext("Bounced"),
        big: assigns.stats.total_bounced,
        unit: gettext("contacts"),
        sub:
          gettext("%{rate}% bounce rate",
            rate: assigns.stats.bounce_rate
          ),
        tone: bounce_tone(assigns.stats.bounce_rate)
      }
    ]

    assigns = assign(assigns, tiles: tiles)

    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-3">
      <%= for t <- @tiles do %>
        <% active? = @selected_bucket == t.k %>
        <% tone = Map.get(t, :tone) %>
        <.link
          patch={~p"/campaigns/#{@campaign_id}/sending-funnel/#{to_string(t.k)}"}
          style={"box-shadow: #{if active?, do: "0 0 0 1px var(--accentRing), var(--shadow-card)", else: "var(--shadow)"};"}
          class={[
            "no-underline text-left p-[13px] cursor-pointer flex flex-col gap-0.5 min-h-[96px] rounded-[11px] border transition-colors",
            if(active?,
              do: "bg-accentSoft border-accentRing",
              else: "bg-card border-border hover:bg-bgSoft"
            )
          ]}
        >
          <div class={[
            "flex items-center gap-1.5 text-[11.5px] font-semibold",
            if(active?, do: "text-accent", else: "text-inkSoft")
          ]}>
            <span :if={Map.get(t, :pulse)} class="relative w-[7px] h-[7px] shrink-0">
              <span class="absolute inset-0 rounded-full bg-green" />
              <span class="absolute -inset-[3px] rounded-full bg-green opacity-40 animate-[pulse-halo_1.8s_ease-out_infinite]" />
            </span>
            {t.label}
          </div>
          <div class={[
            "text-[27px] font-bold leading-[1.05] tracking-[-0.02em] tabular-nums mt-0.5",
            if(active?, do: "text-accent", else: "text-ink")
          ]}>
            {t.big}
          </div>
          <div class={[
            "text-[11.5px] min-h-[14px] tabular-nums",
            tone == :fail && "text-red",
            tone == :warn && "text-amber",
            tone not in [:fail, :warn] && "text-inkFaint"
          ]}>
            {t.sub}
          </div>
        </.link>
      <% end %>
    </div>
    """
  end

  defp failure_rate(_, 0), do: 0

  defp failure_rate(buckets, total),
    do: round(Map.get(buckets, :failed, 0) / total * 100)

  defp bounce_tone(rate) when is_number(rate) and rate >= 5.0, do: :fail
  defp bounce_tone(rate) when is_number(rate) and rate >= 3.0, do: :warn
  defp bounce_tone(_), do: :default

  attr :bucket, :any, default: nil
  attr :campaign_id, :string, required: true

  defp empty_pane(assigns) do
    bucket_label =
      case assigns.bucket do
        nil -> gettext("this bucket")
        b -> b |> Atom.to_string() |> String.replace("_", " ")
      end

    assigns = assign(assigns, bucket_label: bucket_label)

    ~H"""
    <div
      class="h-full bg-bgSoft border border-border rounded-[11px] flex flex-col items-center justify-center text-center px-8 py-16 gap-4"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="text-[64px] font-bold leading-none text-ink20">0</div>
      <div class="text-[22px] font-semibold tracking-[-0.01em] text-ink">
        {raw(
          gettext("Nothing in <em class=\"text-accent italic font-semibold\">%{bucket}</em> yet.",
            bucket: @bucket_label
          )
        )}
      </div>
      <div class="text-[13px] text-inkSoft max-w-[360px] leading-[1.55]">
        {gettext("Pick another tile above, or approve more contacts under")}
        <.link
          navigate={~p"/campaigns/#{@campaign_id}/write"}
          class="text-accent font-medium hover:underline"
        >
          {gettext("Write")}
        </.link>
        {gettext("to feed the funnel.")}
      </div>
    </div>
    """
  end

  attr :campaign, :map, required: true
  attr :stats, :map, required: true

  defp tracking_strip(assigns) do
    ~H"""
    <div
      class="mt-3 flex gap-6 bg-card border border-border rounded-[8px] px-3.5 py-2.5"
      style="box-shadow:var(--shadow)"
    >
      <div :if={@campaign.tracking_opens?} class="flex items-center gap-2 text-[12px] text-inkSoft">
        <span class="font-semibold text-inkSoft">{gettext("Opens")}</span>
        <b class="text-ink font-bold tabular-nums">{@stats.open_rate}%</b>
        <span class="text-inkFaint tabular-nums">({@stats.total_opened}/{@stats.total_sent})</span>
      </div>
      <div :if={@campaign.tracking_clicks?} class="flex items-center gap-2 text-[12px] text-inkSoft">
        <span class="font-semibold text-inkSoft">{gettext("Clicks")}</span>
        <b class="text-ink font-bold tabular-nums">{@stats.click_rate}%</b>
        <span class="text-inkFaint tabular-nums">({@stats.total_clicked}/{@stats.total_sent})</span>
      </div>
    </div>
    """
  end

  attr :contacts, :list, required: true
  attr :selected, :map, default: nil
  attr :selected_bucket, :any, default: nil
  attr :sent_steps, :map, default: %{}
  attr :total_steps, :integer, default: 0
  attr :campaign_id, :string, required: true

  defp contact_list(assigns) do
    ~H"""
    <div
      class="h-full flex flex-col min-h-0 bg-card border border-border rounded-[11px] overflow-hidden"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="flex-none px-4 py-[13px] border-b border-border flex items-center justify-between">
        <div class="text-[13.5px] font-semibold text-ink">
          <span :if={@selected_bucket} class="text-accent capitalize">
            {@selected_bucket |> Atom.to_string() |> String.replace("_", " ")}
          </span>
        </div>
        <div class="text-[12px] font-medium text-inkFaint tabular-nums">
          {gettext("%{n} contacts", n: length(@contacts))}
        </div>
      </div>
      <div class="flex-1 overflow-y-auto p-2">
        <%= for c <- @contacts do %>
          <% active? = @selected && @selected.id == c.id %>
          <% {label, tone} = status_label(c) %>
          <.link
            patch={
              ~p"/campaigns/#{@campaign_id}/sending-funnel/#{to_string(@selected_bucket)}/#{c.id}"
            }
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
                {(c.person && c.person.title) || ""}
              </div>
              <div class={["flex items-center gap-1.5 mt-[3px] text-[11px] font-medium text-#{tone}"]}>
                <span class={"w-[5px] h-[5px] rounded-full shrink-0 bg-#{tone}"} />
                <span class="truncate">{label}</span>
              </div>
            </div>
            <span
              :if={@total_steps > 0}
              class={[
                "shrink-0 text-[12px] font-semibold rounded-[6px] px-[7px] py-0.5 tabular-nums",
                if(active?, do: "bg-[#dbe7fa] text-accent", else: "bg-paperAlt text-inkSoft")
              ]}
            >
              {Map.get(@sent_steps, c.id, 0)}/{@total_steps}
            </span>
          </.link>
        <% end %>
      </div>
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
    company = assigns.contact.person && assigns.contact.person.company

    assigns =
      assign(assigns,
        status_text: status_text,
        status_tone: status_tone,
        recipient: recipient,
        company: company,
        registry_link: Colt.CompanyRegistry.link(company),
        from_name: from_display(assigns.contact.assigned_email_account),
        overrides: ManualOverride.overrides()
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
                    :if={@registry_link}
                    href={@registry_link.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="text-accent font-medium hover:underline"
                  >
                    ↗ {@registry_link.label}
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
                <div :if={@from_name} class="text-inkFaint mt-1">
                  {gettext("From:")} {@from_name}
                </div>
              </div>
            </div>
          </div>

          <div class="flex items-center gap-2.5 flex-wrap shrink-0 relative">
            <button
              type="button"
              phx-click={JS.toggle(to: "#status-menu-#{@contact.id}")}
              class={[
                "inline-flex items-center gap-1.5 rounded-[8px] px-[11px] py-[7px] text-[12.5px] font-semibold cursor-pointer border",
                status_ctl_class(@status_tone)
              ]}
            >
              <span class={["w-[7px] h-[7px] rounded-full", status_dot_class(@status_tone)]} />
              {@status_text} <span class="opacity-70 text-[10px]">▾</span>
            </button>
            <div
              id={"status-menu-#{@contact.id}"}
              class="hidden absolute right-0 top-full mt-1 bg-card border border-border rounded-[8px] z-20 min-w-[180px] py-1"
              style="box-shadow:var(--shadow-card)"
              phx-click-away={JS.hide(to: "#status-menu-#{@contact.id}")}
            >
              <%= for o <- @overrides do %>
                <button
                  phx-click={
                    JS.push("mark_as", value: %{override: o})
                    |> JS.hide(to: "#status-menu-#{@contact.id}")
                  }
                  class="block w-full text-left px-3 py-2 text-[12.5px] text-inkSoft hover:bg-paperAlt"
                >
                  {format_override(o)}
                </button>
              <% end %>
            </div>

            <Liid.btn
              size={:small}
              phx-click="stop_sequence"
              disabled={terminal?(@contact.status)}
            >
              {gettext("Stop sequence")}
            </Liid.btn>
          </div>
        </div>
      </div>

      <%= if @timeline == [] do %>
        <div
          class="flex-none bg-card border border-border rounded-[11px] px-5 py-4 text-[12.5px] text-inkFaint"
          style="box-shadow:var(--shadow)"
        >
          {gettext("No messages yet. The first step will appear here once it sends.")}
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
    """
  end

  attr :item, :map, required: true

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
    # Inbound emails wrap an InboundEmail struct, which has no :status.
    status = if outbound?, do: assigns.item.email.status, else: nil
    sent? = outbound? and status == :sent
    draft? = outbound? and status == :drafted
    queued? = outbound? and status == :approved

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
      if inbound? do
        assigns.item.email.subject
      else
        assigns.item.email.user_subject || assigns.item.email.ai_subject
      end

    sender = if inbound?, do: assigns.item.email.from_address, else: gettext("You")

    assigns =
      assign(assigns,
        outbound?: outbound?,
        inbound?: inbound?,
        manual?: manual?,
        sent?: sent?,
        draft?: draft?,
        queued?: queued?,
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
            :if={@manual?}
            class="inline-flex items-center text-[11px] font-semibold px-2 py-[3px] rounded-[6px] bg-[#f0ecfb] text-[#7a5fc0]"
          >
            {gettext("Manual")}
          </span>
          <span
            :if={@sent?}
            class="inline-flex items-center text-[11px] font-semibold px-2 py-[3px] rounded-[6px] bg-greenSoft text-green"
          >
            {gettext("Sent")}
          </span>
          <span
            :if={@queued?}
            class="inline-flex items-center text-[11px] font-semibold px-2 py-[3px] rounded-[6px] bg-paperAlt text-inkSoft"
          >
            {gettext("Queued")}
          </span>
          <span
            :if={@draft?}
            class="inline-flex items-center text-[11px] font-semibold px-2 py-[3px] rounded-[6px] bg-paperAlt text-inkSoft"
          >
            {gettext("Draft")}
          </span>
          <span
            :if={@outbound? and @item.email.status == :scheduled}
            class="inline-flex items-center text-[11px] font-semibold px-2 py-[3px] rounded-[6px] bg-paperAlt text-inkSoft"
          >
            {gettext("Scheduled")}
          </span>
          <span
            :if={@outbound? and @item.email.status == :bounced}
            class="inline-flex items-center text-[11px] font-semibold px-2 py-[3px] rounded-[6px] bg-amberSoft text-amber"
          >
            {gettext("Bounced")}
          </span>
          <span
            :if={@outbound? and @item.email.status == :failed}
            class="inline-flex items-center text-[11px] font-semibold px-2 py-[3px] rounded-[6px] bg-redSoft text-red"
          >
            {gettext("Failed")}
          </span>
          <span
            :if={@outbound? and @item.email.status == :skipped}
            class="inline-flex items-center text-[11px] font-semibold px-2 py-[3px] rounded-[6px] bg-paperAlt text-inkFaint"
          >
            {gettext("Skipped")}
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

  # Inbound + manual-reply bodies arrive as HTML; outbound AI drafts are
  # plain text. Strip tags for a uniform read-only timeline display.
  defp body_text(text) when is_binary(text) do
    text
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/[ \t]+\n/, "\n")
    |> String.replace(~r/\n[ \t]+/, "\n")
    |> String.trim()
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
        <trix-editor
          input={"trix-content-#{@reply_nonce}"}
          class="trix-content"
          style="min-height:120px;"
        >
        </trix-editor>
        <div class="mt-3 flex justify-end">
          <button
            phx-click="send_reply"
            disabled={@sending?}
            class="inline-flex items-center gap-1.5 bg-accent text-white rounded-[8px] px-[18px] py-[9px] text-[13px] font-semibold cursor-pointer disabled:opacity-60"
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
