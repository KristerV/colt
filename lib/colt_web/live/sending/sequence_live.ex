defmodule ColtWeb.Sending.SequenceLive do
  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, Sequence, SequenceStep}
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}
  on_mount {ColtWeb.Sending.PanicHook, :default}

  @languages [
    {"en", "English"},
    {"et", "Estonian"},
    {"fi", "Finnish"},
    {"sv", "Swedish"},
    {"de", "German"}
  ]

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        campaign = maybe_mark_initialized(campaign, actor)
        sequence = ensure_sequence(campaign, actor)
        steps = load_steps(sequence.id)

        {:ok,
         assign(socket,
           page_title: "Sequence — #{campaign.name}",
           campaign: campaign,
           sequence: sequence,
           steps: steps,
           languages: @languages,
           saved_at: nil
         )}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_event("set_language", %{"language" => lang}, socket) do
    {:ok, sequence} =
      Sequence.set_language(socket.assigns.sequence, lang, actor: socket.assigns.current_user)

    {:noreply, socket |> assign(sequence: sequence) |> mark_saved()}
  end

  def handle_event("set_delay", %{"step_id" => id, "value" => raw}, socket) do
    days =
      case Integer.parse(to_string(raw)) do
        {n, _} when n >= 0 -> n
        _ -> 0
      end

    with {:ok, step} <- SequenceStep.get(id, actor: socket.assigns.current_user),
         {:ok, _} <- SequenceStep.set_delay(step, days, actor: socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(steps: load_steps(socket.assigns.sequence.id))
       |> mark_saved()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_terminal_action", %{"step_id" => id, "value" => v}, socket) do
    action =
      case v do
        "call_ready" -> :call_ready
        _ -> :no_reply
      end

    with {:ok, step} <- SequenceStep.get(id, actor: socket.assigns.current_user),
         {:ok, _} <-
           SequenceStep.set_terminal_action(step, action, actor: socket.assigns.current_user),
         {:ok, sequence} <-
           Sequence.bump_version(socket.assigns.sequence, actor: socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(sequence: sequence, steps: load_steps(socket.assigns.sequence.id))
       |> mark_saved()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("add_step", _params, socket) do
    actor = socket.assigns.current_user
    steps = socket.assigns.steps
    terminal = Enum.find(steps, &(&1.kind == :terminal))
    email_steps = Enum.filter(steps, &(&1.kind == :email))
    new_position = length(email_steps)

    if terminal, do: shift_position(terminal, new_position + 1, actor)

    {:ok, _} =
      SequenceStep.create(socket.assigns.sequence.id, new_position, :email, 2, actor: actor)

    {:ok, sequence} = Sequence.bump_version(socket.assigns.sequence, actor: actor)

    {:noreply,
     socket
     |> assign(sequence: sequence, steps: load_steps(socket.assigns.sequence.id))
     |> mark_saved()}
  end

  def handle_event("remove_step", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, step} <- SequenceStep.get(id, actor: actor),
         true <- step.kind == :email,
         :ok <- SequenceStep.delete_step(step, actor: actor) do
      reindex_email_steps(socket.assigns.sequence.id, actor)
      {:ok, sequence} = Sequence.bump_version(socket.assigns.sequence, actor: actor)

      {:noreply,
       socket
       |> assign(sequence: sequence, steps: load_steps(socket.assigns.sequence.id))
       |> mark_saved()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_auto_approve", _params, socket) do
    campaign = socket.assigns.campaign

    if campaign.auto_approve_unlocked? do
      {:ok, campaign} =
        Colt.Resources.Campaign.set_auto_approve_on(
          campaign,
          !campaign.auto_approve_on?,
          actor: socket.assigns.current_user
        )

      {:noreply, socket |> assign(campaign: campaign) |> mark_saved()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_tracking", %{"field" => field}, socket) do
    campaign = socket.assigns.campaign

    {opens, clicks} =
      case field do
        "opens" -> {!campaign.tracking_opens?, campaign.tracking_clicks?}
        "clicks" -> {campaign.tracking_opens?, !campaign.tracking_clicks?}
      end

    {:ok, campaign} =
      Campaign.set_tracking(campaign, opens, clicks, actor: socket.assigns.current_user)

    {:noreply, socket |> assign(campaign: campaign) |> mark_saved()}
  end

  defp ensure_sequence(campaign, actor) do
    case Sequence.get_for_campaign(campaign.id, actor: actor) do
      {:ok, %_{} = sequence} ->
        sequence

      _ ->
        {:ok, sequence} = Sequence.create_default(campaign.id, actor: actor)
        sequence
    end
  end

  defp maybe_mark_initialized(%{sending_initialized?: true} = campaign, _actor), do: campaign

  defp maybe_mark_initialized(campaign, actor) do
    case Campaign.mark_sending_initialized(campaign, actor: actor) do
      {:ok, c} -> c
      _ -> campaign
    end
  end

  defp load_steps(sequence_id) do
    case SequenceStep.list_for_sequence(sequence_id, authorize?: false) do
      {:ok, steps} -> steps
      _ -> []
    end
  end

  defp shift_position(step, new_position, actor) do
    SequenceStep.set_position!(step, new_position, actor: actor)
  end

  defp reindex_email_steps(sequence_id, actor) do
    steps = load_steps(sequence_id)
    email_steps = Enum.filter(steps, &(&1.kind == :email))
    terminal = Enum.find(steps, &(&1.kind == :terminal))

    email_steps
    |> Enum.with_index()
    |> Enum.each(fn {step, idx} ->
      if step.position != idx, do: shift_position(step, idx, actor)
    end)

    if terminal && terminal.position != length(email_steps),
      do: shift_position(terminal, length(email_steps), actor)
  end

  defp mark_saved(socket), do: assign(socket, saved_at: DateTime.utc_now())

  def render(assigns) do
    email_steps = Enum.filter(assigns.steps, &(&1.kind == :email))
    terminal = Enum.find(assigns.steps, &(&1.kind == :terminal))

    assigns =
      assign(assigns,
        email_steps: email_steps,
        terminal: terminal,
        tracking_on?: assigns.campaign.tracking_opens? || assigns.campaign.tracking_clicks?
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:sequence}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="w-full max-w-[760px] mx-auto pb-16">
        <Liid.headline
          kicker="Sending · Sequence"
          sub="One template, applied to every approved contact. The AI rewrites the body per contact; the structure (steps, waits, terminal action) is fixed here."
        >
          The <em>shape</em> of every email we'll send.
        </Liid.headline>

        <div class="mt-2 font-mono text-[10px] tracking-[0.14em] uppercase text-ink40">
          version {@sequence.version}
        </div>

        <div class="mt-10 flex flex-col gap-0">
          <%= for {step, idx} <- Enum.with_index(@email_steps) do %>
            <.wait :if={idx > 0} days={step.delay_days} id={step.id} terminal={false} />
            <.step_block step={step} idx={idx} />
          <% end %>

          <button
            type="button"
            phx-click="add_step"
            class="mt-3 py-3 border border-dashed border-ink20 text-ink55 font-mono text-[11px] tracking-[0.08em] uppercase rounded-[2px] cursor-pointer hover:border-ink40 hover:text-ink"
          >
            + add follow-up
          </button>

          <%= if @terminal do %>
            <.wait days={@terminal.delay_days} id={@terminal.id} terminal={true} />
            <.terminal_block step={@terminal} />
          <% end %>
        </div>

        <.section_divider label="Language" />
        <.setting_row
          label="Drafts written in"
          hint="The AI will write every subject + body in this language."
        >
          <form phx-change="set_language" class="inline-flex">
            <select
              name="language"
              class="px-3 py-1.5 border border-ink20 bg-paper text-[12px] text-ink rounded-[2px] outline-none cursor-pointer"
            >
              <%= for {code, label} <- @languages do %>
                <option value={code} selected={@sequence.language == code}>{label}</option>
              <% end %>
            </select>
          </form>
        </.setting_row>

        <.section_divider label="Tracking" />
        <.setting_row
          label="Open tracking"
          hint="Pixel embedded in every email. Requires a CNAME you set up yourself."
        >
          <.toggle on={@campaign.tracking_opens?} field="opens" />
        </.setting_row>
        <.setting_row
          label="Click tracking"
          hint="Wraps every link through a redirector on the same CNAME."
        >
          <.toggle on={@campaign.tracking_clicks?} field="clicks" />
        </.setting_row>
        <.cname_card :if={@tracking_on?} domain={@campaign.tracking_domain} />

        <.section_divider label="Approval" />
        <.auto_approve_row campaign={@campaign} />

        <div :if={@saved_at} class="mt-10 font-mono text-[11px] text-ink40">
          saved {Calendar.strftime(@saved_at, "%H:%M:%S")}
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── partials ───────────────────────────────────────────────────────────
  attr :step, :map, required: true
  attr :idx, :integer, required: true

  defp step_block(assigns) do
    ~H"""
    <div class="border border-rule rounded-[2px] bg-paper overflow-hidden">
      <div class="flex items-center gap-3.5 px-[18px] py-3 bg-paperAlt border-b border-rule">
        <span
          class="inline-flex items-center justify-center w-[22px] h-[22px] rounded-full font-mono text-[11px] font-semibold"
          style="background: var(--ink); color: var(--paper);"
        >
          {@idx + 1}
        </span>
        <span class="text-[14px] font-medium text-ink">
          {if @idx == 0, do: "First email", else: "Follow-up #{@idx}"}
        </span>
        <span class="flex-1" />
        <button
          :if={@idx > 0}
          type="button"
          phx-click="remove_step"
          phx-value-id={@step.id}
          class="text-ink40 hover:text-fail cursor-pointer"
          aria-label="Remove step"
        >
          <ColtWeb.Components.Liid.icon name="x" size={12} />
        </button>
      </div>
    </div>
    """
  end

  attr :step, :map, required: true

  defp terminal_block(assigns) do
    ~H"""
    <div class="border border-dashed border-ink20 rounded-[2px] bg-paperAlt px-[18px] py-4 flex items-center gap-3.5">
      <span class="inline-flex items-center justify-center w-[22px] h-[22px] rounded-full border border-ink40 text-ink55 font-mono text-[11px] font-semibold">
        ×
      </span>
      <span class="text-[13px] text-ink70">If still no reply, mark contact as</span>
      <form phx-change="set_terminal_action" class="inline-flex">
        <input type="hidden" name="step_id" value={@step.id} />
        <select
          name="value"
          class="px-3 py-1 border border-ink20 bg-paper text-[12px] font-mono text-ink rounded-[2px] outline-none cursor-pointer"
        >
          <option value="no_reply" selected={@step.terminal_action in [nil, :no_reply]}>
            no_reply
          </option>
          <option value="call_ready" selected={@step.terminal_action == :call_ready}>
            call_ready
          </option>
        </select>
      </form>
      <span class="flex-1" />
      <span class="font-mono text-[10px] tracking-[0.04em] text-ink40">end of sequence</span>
    </div>
    """
  end

  attr :days, :integer, required: true
  attr :id, :string, required: true
  attr :terminal, :boolean, default: false

  defp wait(assigns) do
    ~H"""
    <div class="relative pl-8 py-3.5 flex items-center gap-3.5">
      <span class="absolute left-[14px] top-0 bottom-0 w-px bg-ink20" />
      <span class="absolute left-[9px] top-[calc(50%-5px)] w-[11px] h-[11px] rounded-full bg-paper border border-ink20" />
      <span class="font-mono text-[11px] tracking-[0.06em] text-ink55 inline-flex items-center gap-2">
        wait
        <form phx-change="set_delay" class="inline-flex">
          <input type="hidden" name="step_id" value={@id} />
          <input
            type="number"
            name="value"
            value={@days}
            min="0"
            phx-debounce="400"
            class="w-[52px] px-1.5 py-1 border border-ink20 rounded-[2px] font-mono text-[12px] text-center bg-paper text-ink tabular-nums outline-none"
          />
        </form>
        days
        <span :if={@terminal} class="font-mono text-[11px] tracking-[0.04em] text-ink40">
          · then
        </span>
      </span>
    </div>
    """
  end

  attr :label, :string, required: true

  defp section_divider(assigns) do
    ~H"""
    <div class="mt-10 mb-4 pb-2 border-b border-rule font-mono text-[10px] tracking-[0.14em] uppercase text-ink55">
      {@label}
    </div>
    """
  end

  attr :label, :string, required: true
  attr :hint, :string, default: nil
  slot :inner_block, required: true

  defp setting_row(assigns) do
    ~H"""
    <div class="grid grid-cols-[1fr_auto] gap-6 py-3.5 border-b border-rule items-center">
      <div>
        <div class="text-[13px] text-ink font-medium mb-0.5">{@label}</div>
        <div :if={@hint} class="text-[12px] text-ink55 leading-[1.5]">{@hint}</div>
      </div>
      <div>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :on, :boolean, required: true
  attr :field, :string, required: true

  defp toggle(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_tracking"
      phx-value-field={@field}
      class={[
        "relative inline-block w-[34px] h-[18px] rounded-full cursor-pointer transition-colors",
        if(@on, do: "", else: "bg-ink20")
      ]}
      style={@on && "background: var(--accent);"}
      aria-pressed={@on}
    >
      <span
        class="absolute top-[2px] w-[14px] h-[14px] rounded-full bg-paper transition-all"
        style={"left: #{if @on, do: 18, else: 2}px; box-shadow: 0 1px 2px rgba(0,0,0,0.2);"}
      />
    </button>
    """
  end

  attr :domain, :any, default: nil

  defp cname_card(assigns) do
    ~H"""
    <div class="mt-3.5 p-5 bg-paperAlt border border-rule rounded-[2px]">
      <div class="flex items-baseline justify-between mb-3.5">
        <div>
          <div class="text-[13px] text-ink font-medium">Tracking CNAME</div>
          <div class="text-[12px] text-ink55 mt-0.5">
            Required for opens/clicks. One CNAME at your DNS provider, reused across all sending accounts. Configure under <span class="font-mono text-ink70">/admin/tracking-domain</span>.
          </div>
        </div>
        <span class="font-mono text-[10px] tracking-[0.06em] uppercase text-ink40 px-2 py-0.5 border border-ink20 rounded-[2px]">
          {if @domain, do: "set", else: "unset"}
        </span>
      </div>
    </div>
    """
  end

  attr :campaign, :map, required: true

  defp auto_approve_row(assigns) do
    ~H"""
    <div class={[
      "p-5 border rounded-[2px] flex items-start gap-4",
      if(@campaign.auto_approve_unlocked?,
        do: "bg-paper border-ink20",
        else: "bg-paperAlt border-rule"
      )
    ]}>
      <div class="flex-1">
        <div class="flex items-center gap-2.5 mb-1">
          <span class="text-[13px] text-ink font-medium">Auto-approve drafts</span>
          <span
            :if={!@campaign.auto_approve_unlocked?}
            class="font-mono text-[9px] tracking-[0.14em] uppercase text-ink55 px-1.5 py-0.5 border border-ink20 rounded-[2px]"
          >
            locked
          </span>
          <span
            :if={@campaign.auto_approve_unlocked?}
            class="font-mono text-[9px] tracking-[0.14em] uppercase font-semibold px-1.5 py-0.5 rounded-[2px]"
            style="color: var(--accent); background: color-mix(in oklch, var(--accent) 8%, transparent); border: 1px solid color-mix(in oklch, var(--accent) 35%, transparent);"
          >
            unlocked
          </span>
        </div>
        <div :if={!@campaign.auto_approve_unlocked?} class="text-[12px] text-ink55 leading-[1.5]">
          Unlocks after you've accepted <span class="text-ink">10 AI drafts</span>
          unchanged. You've cleanly accepted <span class="text-ink font-mono">{@campaign.auto_approve_streak} / 10</span>.
        </div>
        <div :if={@campaign.auto_approve_unlocked?} class="text-[12px] text-ink55 leading-[1.5]">
          New contacts go straight to scheduled without landing in the Writing queue.
        </div>
        <div
          :if={!@campaign.auto_approve_unlocked?}
          class="mt-3 h-[4px] bg-ink10 rounded-[1px] relative max-w-[360px] overflow-hidden"
        >
          <div
            class="absolute left-0 top-0 bottom-0"
            style={"width: #{min(100, div(@campaign.auto_approve_streak * 100, 10))}%; background: var(--accent);"}
          />
        </div>
      </div>
      <button
        :if={@campaign.auto_approve_unlocked?}
        phx-click="toggle_auto_approve"
        type="button"
        class={[
          "shrink-0 inline-flex items-center gap-2 px-3 py-1.5 rounded-[2px] border font-mono text-[10px] uppercase tracking-[0.08em] cursor-pointer",
          if(@campaign.auto_approve_on?,
            do: "bg-ink text-paper border-ink",
            else: "bg-transparent text-ink55 border-ink20"
          )
        ]}
      >
        <span
          class="w-[7px] h-[7px] rounded-full"
          style={
            if(@campaign.auto_approve_on?,
              do:
                "background: var(--accent); box-shadow: 0 0 0 3px color-mix(in oklch, var(--accent) 18%, transparent);",
              else: "background: var(--ink40);"
            )
          }
        />
        {if @campaign.auto_approve_on?, do: "ON", else: "OFF"}
      </button>
    </div>
    """
  end
end
