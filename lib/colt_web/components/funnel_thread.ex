defmodule ColtWeb.Components.FunnelThread do
  @moduledoc """
  Shared list+thread funnel UI for the **sending** and **sales** funnels.

  The conversation thread pane — a fixed header carrying the whole contact UI,
  a scrolling timeline of email / note / status cards, and the Reply/Note
  composer — is identical in both funnels, so it lives here once. Improve it
  here and both funnels change together.

  What legitimately differs between the two funnels stays in each LiveView and
  is injected through slots:

    * the top strip (bucket strip vs enrichment table) — not part of this
      component,
    * `:actions` — the right-hand header controls (`Outcome` / `Next action`
      vs `Mark as…` / `Stop sequence`),
    * `:bar_items` — compact middle-of-header controls (the sales checklist),
    * `:info_actions` — buttons inside the contact-info disclosure (Edit).

  The composer emits plain events (`switch_tab`, `trix_input`, `set_note`,
  `send_reply`, `save_note`) that both host LiveViews already handle
  identically, and `build_timeline/4` merges the four timeline sources the same
  way for both.
  """
  use Phoenix.Component
  use Gettext, backend: ColtWeb.Gettext

  alias Colt.Resources.StatusEvent
  alias Colt.Services.Email.RenderBody
  alias ColtWeb.Components.Liid
  alias Phoenix.LiveView.JS

  # A sequence step that's neither sent nor scheduled has no real moment in
  # time — its inserted_at is just when the draft row was written. Pin those to
  # the very end, in step order, with no display date.
  @unscheduled_sentinel ~U[9999-01-01 00:00:00.000000Z]

  @doc """
  Merge outbound + inbound emails, notes, and status events into one
  chronologically sorted timeline. `events` is optional so older callers keep
  working.
  """
  def build_timeline(outbound, inbound, notes, events \\ []) do
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

  @doc """
  The right-hand thread pane: a fixed header of contact controls, then a
  scrolling body holding the timeline and the composer.
  """
  attr :contact, :map, required: true
  attr :timeline, :list, required: true
  attr :recipient, :string, default: ""
  attr :registry_link, :any, default: nil
  attr :from_name, :any, default: nil
  attr :active_tab, :atom, required: true
  attr :reply_html, :string, required: true
  attr :reply_nonce, :integer, required: true
  attr :note_body, :string, required: true
  attr :sending?, :boolean, default: false
  attr :error, :any, default: nil
  attr :insert_links, :list, default: []

  attr :transcript, :string,
    default: "",
    doc: """
    The whole conversation as plain text (`Colt.Services.Export.ThreadTranscript`),
    for the copy-for-AI button. Empty string hides the button.
    """

  slot :actions,
    required: true,
    doc: "Right-hand controls on the pinned bar (outcome, next action, mark-as…)."

  slot :bar_items,
    doc: """
    Funnel-specific compact controls in the middle of the pinned bar. The sales
    funnel puts its checklist summary here; the sending funnel passes nothing.
    """

  slot :info_actions,
    doc: "Buttons inside the contact-info disclosure — currently just Edit."

  def thread_pane(assigns) do
    company = assigns.contact.person && assigns.contact.person.company

    assigns =
      assign(assigns,
        company: company,
        info_id: "contact-info-#{assigns.contact.id}"
      )

    ~H"""
    <%!-- Same shape as the contact list: one bounded card, a fixed header, a
         scrolling body. The header is the entire contact UI — everything you
         need to work someone, on a row that can't scroll away. The detail (who
         they are, where they work, what's left on the checklist) collapses into
         disclosures, because it's reference material you consult occasionally,
         not something worth a permanent card above every thread.

         Unlike the contact list this card has no `overflow-hidden`: the
         header's disclosures hang below it and would be clipped. The body
         rounds its own bottom corners instead. --%>
    <div
      class="h-full flex flex-col min-h-0 bg-card border border-border rounded-[11px]"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="flex-none px-2 py-2 border-b border-border relative z-30">
        <div class="flex items-center gap-1.5 flex-wrap">
          <div class="relative min-w-0">
            <button
              type="button"
              phx-click={JS.toggle(to: "##{@info_id}")}
              class="inline-flex items-center gap-1.5 max-w-[220px] rounded-[8px] px-2.5 py-[7px] text-[13px] font-semibold text-ink hover:bg-paperAlt cursor-pointer"
            >
              <span class="truncate">{(@contact.person && @contact.person.name) || "—"}</span>
              <span class="opacity-50 text-[10px] shrink-0">▾</span>
            </button>

            <div
              id={@info_id}
              class="hidden absolute left-0 top-full mt-1 z-40 w-[290px] bg-card border border-border rounded-[11px] p-4"
              style="box-shadow:var(--shadow-card)"
              phx-click-away={JS.hide(to: "##{@info_id}")}
            >
              <div class="text-[15px] font-bold tracking-[-0.01em] text-ink">
                {(@contact.person && @contact.person.name) || "—"}
              </div>
              <div
                :if={@contact.person && @contact.person.title}
                class="text-[12.5px] text-inkSoft mt-0.5"
              >
                {@contact.person.title}
              </div>

              <%!-- Personal: the human's own contact points, grouped together --%>
              <div class="mt-2 flex flex-col gap-0.5 text-[12px]">
                <span class="text-accent font-medium break-all">{@recipient}</span>
                <a
                  :if={@contact.person && @contact.person.phone}
                  href={"tel:#{@contact.person.phone}"}
                  class="text-accent font-medium hover:underline"
                >
                  ☎ {@contact.person.phone}
                </a>
              </div>

              <%!-- Company: everything about the org, kept separate from the person --%>
              <div :if={@company} class="mt-3 pt-3 border-t border-border text-[12px] text-inkSoft">
                <div class="font-semibold text-ink">{@company.name}</div>
                <div class="flex flex-wrap gap-x-3 gap-y-1 mt-1">
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

              <div :if={@info_actions != []} class="mt-3 pt-3 border-t border-border flex gap-2">
                {render_slot(@info_actions)}
              </div>
            </div>
          </div>

          {render_slot(@bar_items)}

          <%!-- Take the conversation somewhere else to think about it: the
                whole thread as plain text, shaped so a chat AI reads it
                without the markup the pane needs. Copying happens entirely in
                the browser — the text is already here, in the hidden node the
                hook reads. Keyed on the contact so the "Copied" confirmation
                can't linger on someone else's thread. --%>
          <div
            :if={@transcript != ""}
            id={"copy-transcript-#{@contact.id}"}
            phx-hook="CopyText"
            data-copied-label={gettext("Copied")}
          >
            <button
              type="button"
              title={gettext("Copy the whole conversation as plain text, to paste into an AI chat")}
              class="inline-flex items-center gap-1.5 rounded-[8px] px-[11px] py-[7px] text-[12.5px] font-semibold cursor-pointer border bg-card border-border text-inkSoft hover:bg-bgSoft"
            >
              <Liid.icon name="copy" size={11} />
              <span data-copy-label>{gettext("Copy for AI")}</span>
            </button>
            <div class="hidden" data-copy-text phx-no-format>{@transcript}</div>
          </div>

          <div class="ml-auto flex items-center gap-1.5 flex-wrap justify-end shrink-0 relative">
            {render_slot(@actions)}
          </div>
        </div>
      </div>

      <%!-- Keyed on the contact so switching contacts remounts the hook and
           lands you at the newest message rather than at whatever scroll
           offset the previous thread was left at. --%>
      <div
        id={"thread-scroll-#{@contact.id}"}
        phx-hook="ThreadScroll"
        class="flex-1 min-h-0 overflow-y-auto flex flex-col gap-3 p-3 md:p-4 bg-bgSoft rounded-b-[11px]"
      >
        <%= if @timeline == [] do %>
          <div
            class="flex-none bg-card border border-border rounded-[11px] px-5 py-4 text-[12.5px] text-inkFaint"
            style="box-shadow:var(--shadow)"
          >
            {gettext("No messages yet. The first step will appear here once it sends.")}
          </div>
        <% else %>
          <.timeline_item :for={item <- @timeline} item={item} />
        <% end %>

        <.composer
          active_tab={@active_tab}
          reply_html={@reply_html}
          reply_nonce={@reply_nonce}
          note_body={@note_body}
          sending?={@sending?}
          recipient={@recipient}
          insert_links={@insert_links}
          error={@error}
        />
      </div>
    </div>
    """
  end

  @doc "One timeline card — status event, note, or an email (outbound/inbound)."
  attr :item, :map, required: true

  def timeline_item(%{item: %{kind: :status}} = assigns) do
    event = assigns.item.event

    assigns =
      assign(assigns,
        event: event,
        label: event_label(event),
        actor_label: event_actor(event),
        reason: event_reason(event)
      )

    ~H"""
    <div class="flex-none flex justify-center">
      <div
        class="w-full md:w-[72%] max-w-[520px] bg-paperAlt border border-border rounded-[8px] px-3.5 py-2"
        style="box-shadow:var(--shadow)"
      >
        <div class="flex items-center gap-2">
          <.event_marker event={@event} />
          <span class="text-[12px] font-medium text-inkSoft tabular-nums">{@label}</span>
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

  def timeline_item(%{item: %{kind: :note}} = assigns) do
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

  def timeline_item(%{item: %{kind: kind}} = assigns)
      when kind in [:outbound, :manual_outbound, :inbound] do
    outbound? = kind in [:outbound, :manual_outbound]
    inbound? = kind == :inbound
    manual? = kind == :manual_outbound
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

    raw_body =
      if inbound?,
        do: assigns.item.email.body,
        else: assigns.item.email.user_body || assigns.item.email.ai_body || ""

    %{body: body, quoted: quoted} = display_body(raw_body)

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
        draft?: draft?,
        queued?: queued?,
        step_chip: step_chip,
        body: body,
        quoted: quoted,
        subject: subject,
        sender: sender
      )

    ~H"""
    <div class={["flex-none flex", if(@outbound?, do: "md:justify-end", else: "md:justify-start")]}>
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
          <%!-- Sanitized by RenderBody. The card renders the sender's own
                markup, so no whitespace-pre-wrap here — the <br>s are real. --%>
          <div class="email-html text-[13px] leading-[1.55] text-[#4a473f]">
            {Phoenix.HTML.raw(@body)}
          </div>
          <details :if={@quoted} class="mt-2.5">
            <summary class="cursor-pointer list-none select-none inline-flex items-center gap-1.5 text-[11px] font-semibold text-inkFaint hover:text-accent">
              <span class="inline-flex items-center justify-center h-[14px] px-1.5 rounded-[4px] bg-paperAlt border border-border leading-none tracking-[0.08em]">
                ···
              </span>
              {gettext("Quoted text")}
            </summary>
            <div class="email-html mt-2 px-3 py-2.5 rounded-[8px] bg-bgSoft border border-border text-[12.5px] leading-[1.55] text-inkFaint">
              {Phoenix.HTML.raw(@quoted)}
            </div>
          </details>
        </div>
      </div>
    </div>
    """
  end

  @doc "The Reply/Note composer card. Emits switch_tab / trix_input / set_note / send_reply / save_note."
  attr :active_tab, :atom, required: true
  attr :reply_html, :string, required: true
  attr :reply_nonce, :integer, required: true
  attr :note_body, :string, required: true
  attr :sending?, :boolean, default: false
  attr :recipient, :string, required: true
  attr :error, :any, default: nil

  # Links the writer can drop into the reply, as `%{label:, text:, url:}`. Empty
  # by default so a funnel with nothing to offer shows no button. Insertion is
  # pure client-side — see the `liid:insert-link` listener in `TrixEditor`.
  attr :insert_links, :list, default: []

  def composer(assigns) do
    assigns = assign(assigns, has_recipient?: assigns.recipient not in [nil, ""])

    ~H"""
    <div
      class="flex-none bg-card border border-border rounded-[11px] overflow-hidden"
      style="box-shadow:var(--shadow)"
    >
      <div class={[
        "flex items-center gap-1.5 px-2.5 py-2 bg-bgSoft",
        @active_tab && "border-b border-border"
      ]}>
        <button
          phx-click="switch_tab"
          phx-value-tab="reply"
          style={@active_tab == :reply && "box-shadow: inset 0 0 0 1px var(--accentRing)"}
          class={[
            "inline-flex items-center gap-1.5 text-[12.5px] font-semibold px-3 py-1.5 rounded-[7px] cursor-pointer bg-accentSoft text-accent",
            @active_tab != :reply && "opacity-70 hover:opacity-100"
          ]}
        >
          <Liid.icon name="arrow" size={11} /> {gettext("Reply")}
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="note"
          style={@active_tab == :note && "box-shadow: inset 0 0 0 1px #e6c877"}
          class={[
            "inline-flex items-center gap-1.5 text-[12.5px] font-semibold px-3 py-1.5 rounded-[7px] cursor-pointer bg-amberSoft text-[#9a6f17]",
            @active_tab != :note && "opacity-70 hover:opacity-100"
          ]}
        >
          {gettext("Note")}
        </button>
        <%!-- Insertion happens entirely in the browser: the Trix wrapper is
              phx-update="ignore", so a server round trip would have nothing to
              patch. The hook syncs the editor's HTML back afterwards. --%>
        <div
          :if={@active_tab == :reply and @has_recipient? and @insert_links != []}
          class="relative"
        >
          <button
            type="button"
            phx-click={JS.toggle(to: "#insert-menu-#{@reply_nonce}")}
            class="inline-flex items-center gap-1.5 text-[12.5px] font-semibold px-3 py-1.5 rounded-[7px] cursor-pointer border border-border bg-card text-inkSoft hover:bg-paperAlt"
          >
            {gettext("Insert link")}
            <span class="opacity-70 text-[10px]">▾</span>
          </button>
          <div
            id={"insert-menu-#{@reply_nonce}"}
            class="hidden absolute left-0 top-full mt-1 bg-card border border-border rounded-[8px] z-20 min-w-[240px] py-1"
            style="box-shadow:var(--shadow-card)"
            phx-click-away={JS.hide(to: "#insert-menu-#{@reply_nonce}")}
          >
            <button
              :for={link <- @insert_links}
              type="button"
              phx-click={
                JS.dispatch("liid:insert-link",
                  to: "#trix-wrap-#{@reply_nonce}",
                  detail: %{url: link.url, text: link.text}
                )
                |> JS.hide(to: "#insert-menu-#{@reply_nonce}")
              }
              class="flex flex-col w-full text-left px-3 py-2 hover:bg-paperAlt cursor-pointer"
            >
              <span class="text-[12.5px] text-inkSoft font-medium">{link.label}</span>
              <span class="text-[11px] text-inkFaint truncate">{link.text}</span>
            </button>
          </div>
        </div>

        <span
          :if={@active_tab == :reply and @has_recipient?}
          class="ml-auto text-[12px] text-inkFaint font-medium truncate"
        >
          {gettext("To:")} <b class="text-inkSoft font-semibold">{@recipient}</b>
        </span>
      </div>

      <div :if={@error} class="px-3.5 pt-3 text-[12px] text-red">{@error}</div>

      <%!-- No email on file → can't reply. Nudge to add one; don't let them
           write a message that could never send. --%>
      <div :if={@active_tab == :reply and not @has_recipient?} class="px-3.5 py-4">
        <div class="text-[12.5px] text-inkSoft leading-[1.5]">
          {gettext("This contact has no email address yet.")}
          <span class="text-inkFaint">
            {gettext("Add one with Edit before you can reply.")}
          </span>
        </div>
      </div>

      <div
        :if={@active_tab == :reply and @has_recipient?}
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

      <div :if={@active_tab == :note} class="px-3.5 py-3 bg-amberSoft">
        <form id={"note-form-#{@reply_nonce}"} phx-change="set_note">
          <textarea
            id={"note-input-#{@reply_nonce}"}
            name="value"
            rows="4"
            phx-debounce="300"
            placeholder={gettext("Internal note — not sent to recipient.")}
            class="w-full px-3 py-2 bg-card border border-[#f0dcb0] rounded-[8px] text-[13px] text-[#6e5417] outline-none resize-none focus:border-[#e6c877]"
          >{@note_body}</textarea>
        </form>
        <div class="mt-3 flex justify-end">
          <button
            phx-click="save_note"
            class="inline-flex items-center gap-1.5 bg-[#9a6f17] text-white rounded-[8px] px-[18px] py-[9px] text-[13px] font-semibold cursor-pointer"
            style="box-shadow:0 1px 2px rgba(154,111,23,.3)"
          >
            {gettext("Save note")}
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ── Shared presentational helpers (public: the contact list in each funnel
  #    reuses these too) ─────────────────────────────────────────────────

  @doc "Up-to-two-letter initials for the list/thread avatar."
  def initials(name) when is_binary(name) do
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

  def initials(_), do: "?"

  def website_href("http" <> _ = url), do: url
  def website_href(url), do: "https://" <> url

  def website_host(url) do
    case URI.parse(website_href(url)) do
      %URI{host: h} when is_binary(h) -> String.replace_prefix(h, "www.", "")
      _ -> url
    end
  end

  # Inbound + manual-reply bodies arrive as HTML; outbound AI drafts are plain
  # text. Both halves come back sanitized and go through `raw/1` in the card.
  defp display_body(raw) do
    {:ok, split} = RenderBody.run(raw)
    split
  end

  # Feed-line label for a StatusEvent: "from → to", "→ to", or just "to".
  # A checklist tick gets a real checkbox rather than the generic dot — the
  # state *is* the information, and an arrow transition ("→ Demo") read as if
  # the contact had moved somewhere.
  attr :event, :map, required: true

  defp event_marker(%{event: %{kind: :checklist}} = assigns) do
    assigns = assign(assigns, done?: StatusEvent.checklist_done?(assigns.event))

    ~H"""
    <span class={[
      "w-[14px] h-[14px] rounded-[4px] shrink-0 flex items-center justify-center border",
      if(@done?, do: "bg-accent border-accent text-white", else: "bg-card border-borderStrong")
    ]}>
      <%!-- The shared icon is drawn at 1.25 stroke, which disappears at 10px. --%>
      <Liid.icon :if={@done?} name="check" size={10} class="[stroke-width:2.2]" />
    </span>
    """
  end

  defp event_marker(assigns) do
    ~H"""
    <span class="w-[5px] h-[5px] rounded-full bg-inkFaint shrink-0" />
    """
  end

  # The checkbox already says checked-or-not, so the label is just the item.
  defp event_label(%{kind: :checklist, to: item}) when is_binary(item), do: item

  # Entry has only ever meant one thing, and on pre-2026-08-09 rows its `to` is
  # a stage name that no longer exists — so it reads as a sentence, not as a
  # transition into a bucket you can't navigate to.
  defp event_label(%{kind: :entry}), do: gettext("Entered the sales funnel")

  defp event_label(%{from: from, to: to}) when is_binary(from) and is_binary(to),
    do: "#{from} → #{to}"

  defp event_label(%{to: to}) when is_binary(to), do: "→ #{to}"
  defp event_label(%{from: from}) when is_binary(from), do: from
  defp event_label(_), do: gettext("status changed")

  # Both of these carry their meaning in the label/marker; repeating it on a
  # second line ("checked", "entered sales funnel") was pure noise.
  defp event_reason(%{kind: :checklist}), do: nil
  defp event_reason(%{kind: :entry}), do: nil
  defp event_reason(%{reason: reason}), do: reason

  defp event_actor(%{actor: %{email: email}}) when not is_nil(email), do: to_string(email)
  defp event_actor(_), do: gettext("System")
end
