defmodule ColtWeb.Components.FunnelThread do
  @moduledoc """
  Shared list+thread funnel UI for the **sending** and **sales** funnels.

  The conversation thread pane — the company-info header card, the timeline of
  email / note / status cards, and the Reply/Note composer — is identical in
  both funnels, so it lives here once. Improve it here and both funnels change
  together.

  What legitimately differs between the two funnels stays in each LiveView and
  is injected through slots:

    * the top strip (bucket strip vs stage strip) — not part of this component,
    * the thread-header action controls (`Mark as…` / `Stop sequence` vs
      `Move to…`) — the `:actions` slot,
    * an optional panel under the header (e.g. the sales lost-reason prompt) —
      the `:header_panel` slot.

  The composer emits plain events (`switch_tab`, `trix_input`, `set_note`,
  `send_reply`, `save_note`) that both host LiveViews already handle
  identically, and `build_timeline/4` merges the four timeline sources the same
  way for both.
  """
  use Phoenix.Component
  use Gettext, backend: ColtWeb.Gettext

  alias ColtWeb.Components.Liid

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
  The right-hand thread pane: company-info header (with an `:actions` slot for
  the funnel-specific controls and an optional `:header_panel` slot), the
  timeline, and the composer.
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
  slot :actions, required: true
  slot :header_panel

  def thread_pane(assigns) do
    company = assigns.contact.person && assigns.contact.person.company
    assigns = assign(assigns, company: company)

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
            {render_slot(@actions)}
          </div>
        </div>

        {render_slot(@header_panel)}
      </div>

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
        error={@error}
      />
    </div>
    """
  end

  @doc "One timeline card — status event, note, or an email (outbound/inbound)."
  attr :item, :map, required: true

  def timeline_item(%{item: %{kind: :status}} = assigns) do
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

  @doc "The Reply/Note composer card. Emits switch_tab / trix_input / set_note / send_reply / save_note."
  attr :active_tab, :atom, required: true
  attr :reply_html, :string, required: true
  attr :reply_nonce, :integer, required: true
  attr :note_body, :string, required: true
  attr :sending?, :boolean, default: false
  attr :recipient, :string, required: true
  attr :error, :any, default: nil

  def composer(assigns) do
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
  # text. Strip tags for a uniform read-only timeline display.
  defp body_text(text) when is_binary(text) do
    text
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/[ \t]+\n/, "\n")
    |> String.replace(~r/\n[ \t]+/, "\n")
    |> String.trim()
  end

  defp body_text(_), do: ""

  # Feed-line label for a StatusEvent: "from → to", "→ to", or just "to".
  defp event_transition(%{from: from, to: to}) when is_binary(from) and is_binary(to),
    do: "#{from} → #{to}"

  defp event_transition(%{to: to}) when is_binary(to), do: "→ #{to}"
  defp event_transition(%{from: from}) when is_binary(from), do: from
  defp event_transition(_), do: gettext("status changed")

  defp event_actor(%{actor: %{email: email}}) when not is_nil(email), do: to_string(email)
  defp event_actor(_), do: gettext("System")
end
