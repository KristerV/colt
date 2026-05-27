defmodule ColtWeb.Sending.WritingLive do
  @moduledoc """
  Phase E4 — one-contact-at-a-time approval queue.

  States:
    · :loading      — initial mount, picking next contact
    · :empty        — no :pending_approval contacts; promotion button
    · :empty_auto   — auto-approve is on; contacts skip this view
    · :drafting     — contact loaded, EmailWriter still running
    · :default      — drafts loaded; editor + Approve & next
  """

  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, CampaignCompany, CampaignContact, OutboundEmail, Sequence}
  alias Colt.Services.Sending.{ApproveContact, IngestEnriched}
  alias Colt.Services.Sending.EmailWriter
  alias Phoenix.PubSub
  alias ColtWeb.Components.Liid

  @pubsub Colt.PubSub

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}
  on_mount {ColtWeb.Sending.PanicHook, :default}

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        if connected?(socket), do: PubSub.subscribe(@pubsub, topic(campaign.id))

        socket =
          socket
          |> assign(
            page_title: "Writing — #{campaign.name}",
            campaign: campaign,
            state: :loading,
            contact: nil,
            person: nil,
            company: nil,
            drafts: [],
            email_steps: [],
            subject: "",
            bodies: %{},
            enriched_available: 0,
            saved_at: nil
          )
          |> load_next_contact()

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  # ── Events ─────────────────────────────────────────────────────────────

  def handle_event("promote", _params, socket) do
    actor = socket.assigns.current_user
    {:ok, _} = IngestEnriched.run(socket.assigns.campaign.id, actor: actor)
    {:noreply, load_next_contact(socket)}
  end

  def handle_event("set_subject", %{"value" => v}, socket) do
    {:noreply, assign(socket, subject: v) |> mark_saved()}
  end

  def handle_event("set_body", %{"position" => pos, "value" => v}, socket) do
    pos = String.to_integer(pos)
    bodies = Map.put(socket.assigns.bodies, pos, v)
    {:noreply, assign(socket, bodies: bodies) |> mark_saved()}
  end

  def handle_event("approve", _params, socket) do
    actor = socket.assigns.current_user
    contact = socket.assigns.contact

    edits = %{
      "subject" => socket.assigns.subject,
      "bodies" => socket.assigns.bodies
    }

    case ApproveContact.run(contact.id, edits, actor: actor) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Approved — scheduling step 1.") |> load_next_contact()}

      {:error, :no_healthy_inbox} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No healthy sending inbox enrolled in this campaign. Add one under Sending accounts."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't approve: #{inspect(reason)}")}
    end
  end

  # ── Async draft generation ─────────────────────────────────────────────

  def handle_info({:drafts_ready, contact_id}, socket) do
    if socket.assigns.contact && socket.assigns.contact.id == contact_id do
      {:noreply, load_drafts(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:drafts_failed, contact_id, reason}, socket) do
    if socket.assigns.contact && socket.assigns.contact.id == contact_id do
      {:noreply,
       socket
       |> put_flash(:error, "AI writer failed: #{inspect(reason)}")
       |> assign(state: :default)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Internals ──────────────────────────────────────────────────────────

  defp load_next_contact(socket) do
    actor = socket.assigns.current_user
    campaign = socket.assigns.campaign

    cond do
      campaign.auto_approve_on? ->
        assign(socket,
          state: :empty_auto,
          contact: nil,
          drafts: [],
          subject: "",
          bodies: %{}
        )

      true ->
        case CampaignContact.next_pending(campaign.id, actor: actor) do
          {:ok, %_{} = contact} ->
            contact =
              Ash.load!(contact, [person: [:company], thread: []],
                actor: actor,
                authorize?: true
              )

            socket
            |> assign(
              contact: contact,
              person: contact.person,
              company: contact.person && contact.person.company,
              subject: "",
              bodies: %{}
            )
            |> load_drafts_or_start_writer()

          _ ->
            assign(socket,
              state: :empty,
              contact: nil,
              drafts: [],
              subject: "",
              bodies: %{},
              enriched_available: count_enriched_available(campaign.id, actor)
            )
        end
    end
  end

  defp load_drafts_or_start_writer(socket) do
    actor = socket.assigns.current_user
    contact = socket.assigns.contact

    email_steps = sequence_email_steps(contact.campaign_id, actor)
    wanted = Enum.map(email_steps, & &1.position)
    drafts = reconcile_drafts(contact, wanted, actor)
    missing = wanted -- Enum.map(drafts, & &1.step_position)
    socket = assign(socket, email_steps: email_steps)

    cond do
      missing == [] and drafts == [] ->
        kick_off_writer(contact.id, actor)
        assign(socket, state: :drafting, drafts: [])

      missing != [] ->
        kick_off_writer(contact.id, actor)
        socket |> assign(drafts: drafts, state: :drafting) |> seed_inputs_from_drafts(drafts)

      true ->
        socket |> assign(drafts: drafts, state: :default) |> seed_inputs_from_drafts(drafts)
    end
  end

  defp sequence_email_steps(campaign_id, actor) do
    case Sequence.get_for_campaign(campaign_id, load: [:sequence_steps], actor: actor) do
      {:ok, seq} ->
        seq.sequence_steps
        |> Enum.filter(&(&1.kind == :email))
        |> Enum.sort_by(& &1.position)

      _ ->
        []
    end
  end

  # Any outbound Email at a wanted position counts as "already drafted",
  # regardless of status — after approve, those rows are :scheduled or
  # :approved, but they're still the contact's emails and we must not
  # re-run the writer for them. We only delete *unused* :drafted rows at
  # positions that no longer exist in the sequence.
  defp reconcile_drafts(contact, wanted_positions, actor) do
    drafts = list_outbound_drafts(contact, actor)
    wanted = MapSet.new(wanted_positions)

    {keep, drop} =
      Enum.split_with(drafts, fn e -> MapSet.member?(wanted, e.step_position) end)

    Enum.each(drop, fn e ->
      if e.status == :drafted do
        Ash.destroy!(e, actor: actor, authorize?: actor != nil)
      end
    end)

    keep
  end

  defp load_drafts(socket) do
    drafts = list_outbound_drafts(socket.assigns.contact, socket.assigns.current_user)
    socket |> assign(drafts: drafts, state: :default) |> seed_inputs_from_drafts(drafts)
  end

  defp list_outbound_drafts(%{thread: %{id: tid}}, actor) do
    OutboundEmail.list_for_thread!(tid, actor: actor, authorize?: actor != nil)
    |> Enum.sort_by(& &1.step_position)
  end

  defp list_outbound_drafts(_, _), do: []

  defp seed_inputs_from_drafts(socket, drafts) do
    first = List.first(drafts)
    subject = (first && (first.user_subject || first.ai_subject)) || ""

    bodies =
      Enum.into(drafts, %{}, fn e ->
        {e.step_position, e.user_body || e.ai_body || ""}
      end)

    assign(socket, subject: subject, bodies: bodies)
  end

  defp kick_off_writer(contact_id, actor) do
    parent = self()

    Task.start(fn ->
      case EmailWriter.run(contact_id, actor: actor) do
        {:ok, _} -> send(parent, {:drafts_ready, contact_id})
        {:error, reason} -> send(parent, {:drafts_failed, contact_id, reason})
      end
    end)
  end

  defp count_enriched_available(campaign_id, actor) do
    case CampaignCompany.list_for_campaign(campaign_id, actor: actor) do
      {:ok, rows} ->
        picks = Enum.filter(rows, &(&1.picked_person_id != nil))

        existing_person_ids =
          case CampaignContact.list_for_campaign(campaign_id, actor: actor) do
            {:ok, contacts} -> MapSet.new(contacts, & &1.person_id)
            _ -> MapSet.new()
          end

        picks
        |> Enum.reject(&MapSet.member?(existing_person_ids, &1.picked_person_id))
        |> length()

      _ ->
        0
    end
  end

  defp mark_saved(socket), do: assign(socket, saved_at: DateTime.utc_now())

  defp topic(campaign_id), do: "writing:#{campaign_id}"

  # ── Render ─────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:writing}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="w-full max-w-[760px] mx-auto">
        <Liid.headline
          kicker="Sending · Writing"
          sub="One contact at a time. Approve to schedule the first step; the rest follows."
        >
          Draft for <em>this contact</em>.
        </Liid.headline>

        <div class="mt-10">
          <%= case @state do %>
            <% :loading -> %>
              <div class="font-mono text-[11px] text-ink40">loading…</div>
            <% :empty -> %>
              <.empty_state available={@enriched_available} />
            <% :empty_auto -> %>
              <.empty_auto_state />
            <% s when s in [:default, :drafting] -> %>
              <.editor
                contact={@contact}
                person={@person}
                company={@company}
                drafts={@drafts}
                email_steps={@email_steps}
                subject={@subject}
                bodies={@bodies}
                drafting={s == :drafting}
                saved_at={@saved_at}
              />
          <% end %>
        </div>
      </div>

      <.action_bar
        :if={@state in [:default, :drafting]}
        drafting={@state == :drafting}
        can_approve={can_approve?(@subject, @bodies, @drafts)}
      />
    </Layouts.app>
    """
  end

  defp can_approve?(subject, bodies, drafts) do
    subject = String.trim(subject || "")

    drafts != [] and subject != "" and
      Enum.all?(drafts, fn e ->
        case Map.get(bodies, e.step_position) do
          nil -> e.ai_body not in [nil, ""]
          v -> String.trim(v) != ""
        end
      end)
  end

  # ── Partials ───────────────────────────────────────────────────────────

  attr :available, :integer, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center text-center gap-6 py-10">
      <div class="font-serif text-[96px] leading-none text-accent opacity-40">0</div>
      <h2 class="font-serif text-[36px] tracking-[-0.02em] leading-[1.05] m-0 max-w-[520px]">
        Nothing to <em class="text-accent">review</em>.
      </h2>
      <p class="text-[14px] text-ink55 max-w-[460px] leading-[1.6]">
        <span :if={@available > 0}>
          {@available} enriched contacts are waiting to be brought into sending.
        </span>
        <span :if={@available == 0}>
          No enriched contacts are queued. Run enrichment first.
        </span>
      </p>
      <Liid.btn :if={@available > 0} variant={:primary} mono phx-click="promote">
        <Liid.icon name="arrow" size={12} />
        Bring in {@available} enriched {pluralize(@available, "contact")}
      </Liid.btn>
    </div>
    """
  end

  defp pluralize(1, word), do: word
  defp pluralize(_, word), do: word <> "s"

  defp empty_auto_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center text-center gap-6 py-10">
      <div
        class="w-14 h-14 rounded-full flex items-center justify-center"
        style="background: color-mix(in oklch, var(--accent) 12%, transparent);"
      >
        <span
          class="w-3.5 h-3.5 rounded-full"
          style="background: var(--accent); box-shadow: 0 0 0 5px color-mix(in oklch, var(--accent) 15%, transparent);"
        />
      </div>
      <h2 class="font-serif text-[36px] tracking-[-0.02em] leading-[1.05] m-0 max-w-[480px]">
        You're <em class="text-accent">off the hook</em>.
      </h2>
      <p class="text-[14px] text-ink55 max-w-[460px] leading-[1.6]">
        Auto-approve is on. New contacts skip this view and go straight to scheduled.
      </p>
    </div>
    """
  end

  attr :contact, :map, required: true
  attr :person, :map, required: true
  attr :company, :map, default: nil
  attr :drafts, :list, required: true
  attr :email_steps, :list, default: []
  attr :subject, :string, required: true
  attr :bodies, :map, required: true
  attr :drafting, :boolean, default: false
  attr :saved_at, :any, default: nil

  defp editor(assigns) do
    delay_by_position =
      Map.new(assigns.email_steps, fn s -> {s.position, s.delay_days} end)

    assigns = assign(assigns, :delay_by_position, delay_by_position)

    ~H"""
    <.contact_header person={@person} company={@company} />

    <div class="mt-7">
      <div class="font-mono text-[10px] tracking-[0.14em] uppercase text-ink55 mb-2.5">
        How it lands in {first_name(@person)}'s inbox
      </div>
      <.inbox_preview subject={@subject} from={(@person && @person.email) || "you@example.com"} />
    </div>

    <div class="mt-8">
      <div class="font-mono text-[10px] tracking-[0.14em] uppercase text-ink55 mb-2.5">
        Subject
      </div>
      <form phx-change="set_subject" class="block">
        <input
          type="text"
          name="value"
          value={@subject}
          phx-debounce="400"
          placeholder="subject line"
          disabled={@drafting}
          class="w-full px-5 py-3 border border-ink20 border-l-2 bg-paper rounded-[2px] text-[13.5px] text-ink outline-none placeholder:text-ink40"
          style="border-left-color: var(--accent);"
        />
      </form>
      <div class="mt-1.5 font-mono text-[10px] text-ink40">
        follow-ups re-use this subject as “re: …”
      </div>
    </div>

    <div class="mt-7 flex items-baseline justify-between">
      <div class="font-mono text-[10px] tracking-[0.14em] uppercase text-ink55">Sequence draft</div>
      <div
        :if={@drafting}
        class="font-mono text-[10px] tracking-[0.06em] inline-flex items-center gap-1.5"
        style="color: var(--accent);"
      >
        <span
          class="w-[5px] h-[5px] rounded-full"
          style="background: var(--accent); animation: liid-pulse 1.4s ease-in-out infinite;"
        /> drafting…
      </div>
    </div>

    <div class="mt-3 flex flex-col gap-5">
      <%= cond do %>
        <% @drafting and @drafts == [] -> %>
          <.step_skeleton position={0} />
          <.wait_marker days={Map.get(@delay_by_position, 1, 2)} />
          <.step_skeleton position={1} />
          <.wait_marker days={Map.get(@delay_by_position, 2, 2)} />
          <.step_skeleton position={2} />
        <% true -> %>
          <%= for {email, idx} <- Enum.with_index(@drafts) do %>
            <.wait_marker :if={idx > 0} days={Map.get(@delay_by_position, email.step_position, 2)} />
            <.step_card
              email={email}
              idx={idx}
              body={Map.get(@bodies, email.step_position, email.user_body || email.ai_body || "")}
              disabled={@drafting}
            />
          <% end %>
      <% end %>
    </div>

    <div :if={@saved_at} class="mt-6 font-mono text-[11px] text-ink40">
      saved {Calendar.strftime(@saved_at, "%H:%M:%S")}
    </div>
    """
  end

  defp first_name(nil), do: "them"

  defp first_name(%{name: nil}), do: "them"

  defp first_name(%{name: name}) do
    name |> String.split() |> List.first() || "them"
  end

  attr :person, :map, required: true
  attr :company, :map, default: nil

  defp contact_header(assigns) do
    ~H"""
    <div class="p-5 border border-rule bg-paper rounded-[2px]">
      <div class="flex items-baseline justify-between gap-4">
        <div>
          <div class="font-serif text-[28px] tracking-[-0.02em] leading-none text-ink">
            {(@person && @person.name) || "—"}
          </div>
          <div class="mt-1 text-[13px] text-ink55">
            {(@person && @person.title) || "—"}
          </div>
          <div class="mt-1 font-mono text-[11px] text-ink70">
            {(@person && @person.email) || ""}
          </div>
        </div>
        <div :if={@company} class="text-right">
          <div class="text-[14px] font-medium text-ink">{@company.name}</div>
          <div class="font-mono text-[10px] tracking-[0.06em] uppercase text-ink40 mt-0.5">
            {[
              @company.industry_code,
              @company.region,
              @company.employees_latest && "#{@company.employees_latest} emp"
            ]
            |> Enum.reject(&(&1 in [nil, ""]))
            |> Enum.join(" · ")}
          </div>
        </div>
      </div>
      <div
        :if={@company && @company.ai_summary}
        class="mt-3 text-[13px] leading-[1.55] text-ink70 border-t border-rule pt-3"
      >
        {@company.ai_summary}
      </div>
    </div>
    """
  end

  attr :days, :integer, required: true

  defp wait_marker(assigns) do
    ~H"""
    <div class="relative pl-8 flex items-center -my-1">
      <span class="absolute left-[14px] top-0 bottom-0 w-px bg-ink20" />
      <span class="absolute left-[9px] top-[calc(50%-5px)] w-[11px] h-[11px] rounded-full bg-paper border border-ink20" />
      <span class="font-mono text-[11px] tracking-[0.06em] text-ink55 inline-flex items-center gap-2 uppercase">
        wait <span class="text-ink tabular-nums">{@days}</span> days
      </span>
    </div>
    """
  end

  attr :email, :map, required: true
  attr :idx, :integer, required: true
  attr :body, :string, default: ""
  attr :disabled, :boolean, default: false

  defp step_card(assigns) do
    ~H"""
    <div
      class="border border-rule rounded-[2px] bg-paper"
      style={if @idx == 0, do: "border-left: 2px solid var(--accent);", else: ""}
    >
      <div class="flex items-center gap-3.5 px-5 py-3 border-b border-rule bg-paperAlt">
        <span class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink40">
          Step {@idx + 1}
        </span>
        <span class="text-[13px] text-ink">
          {if @idx == 0, do: "First email", else: "Follow-up #{@idx}"}
        </span>
      </div>
      <form phx-change="set_body" class="block">
        <input type="hidden" name="position" value={@email.step_position} />
        <textarea
          name="value"
          rows="6"
          phx-debounce="600"
          disabled={@disabled}
          class="w-full px-5 py-4 bg-paper text-[13.5px] leading-[1.6] text-ink70 outline-none border-0 resize-none font-sans block"
          style="field-sizing: content;"
        >{@body}</textarea>
      </form>
    </div>
    """
  end

  attr :position, :integer, required: true

  defp step_skeleton(assigns) do
    ~H"""
    <div class="border border-rule rounded-[2px] px-5 py-4">
      <div class="flex items-center gap-3 mb-3">
        <span class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink40">
          Step {@position + 1}
        </span>
        <span
          class="inline-flex items-center gap-1.5 font-mono text-[10px]"
          style="color: var(--accent);"
        >
          <span
            class="w-[5px] h-[5px] rounded-full"
            style="background: var(--accent); animation: liid-pulse 1.4s ease-in-out infinite;"
          /> drafting…
        </span>
      </div>
      <div class="h-3 w-[60%] bg-ink10 mb-2" />
      <div class="h-2.5 w-[95%] bg-ink10 mb-1.5" />
      <div class="h-2.5 w-[90%] bg-ink10 mb-1.5" />
      <div class="h-2.5 w-[70%] bg-ink10" />
    </div>
    """
  end

  attr :subject, :string, required: true
  attr :from, :string, required: true

  defp inbox_preview(assigns) do
    fakes = [
      %{
        from: "GitHub",
        subj: "Security alert",
        preview: "A new sign-in to your account",
        time: "10:42"
      },
      %{
        from: "Stripe",
        subj: "Invoice paid",
        preview: "$199.00 received from Acme Co.",
        time: "09:18"
      },
      %{
        from: "Linear",
        subj: "5 issues assigned to you",
        preview: "Q2 planning · sprint 14",
        time: "08:55"
      }
    ]

    assigns = assign(assigns, :fakes, fakes)

    ~H"""
    <div class="border border-rule rounded-[2px] bg-paper overflow-hidden">
      <div class="px-5 py-2 border-b border-rule bg-paperAlt flex items-center gap-3.5">
        <div class="w-[14px] h-[14px] border border-ink40 rounded-[2px]" />
        <span class="text-ink55">⟳</span>
      </div>
      <div>
        <%= for {m, i} <- Enum.with_index(@fakes) do %>
          <%= if i == 2 do %>
            <.gmail_row
              from={@from}
              subj={subject_or_placeholder(@subject)}
              preview=""
              time="now"
              highlight={true}
            />
          <% end %>
          <.gmail_row from={m.from} subj={m.subj} preview={m.preview} time={m.time} highlight={false} />
        <% end %>
      </div>
    </div>
    """
  end

  defp subject_or_placeholder(""), do: "(empty subject)"
  defp subject_or_placeholder(nil), do: "(empty subject)"
  defp subject_or_placeholder(s), do: s

  attr :from, :string, required: true
  attr :subj, :string, required: true
  attr :preview, :string, default: ""
  attr :time, :string, required: true
  attr :highlight, :boolean, default: false

  defp gmail_row(assigns) do
    ~H"""
    <div
      class="grid items-center gap-3.5 px-5 py-2.5 border-b border-rule bg-paper"
      style={
        "grid-template-columns: 18px 18px 180px 1fr 70px;" <>
          if @highlight, do: " box-shadow: inset 2px 0 0 var(--accent);", else: ""
      }
    >
      <div class="w-[14px] h-[14px] rounded-[2px] border border-ink40" />
      <span class="text-ink40">☆</span>
      <span class="text-[13px] truncate font-bold text-ink">{@from}</span>
      <span class="text-[13px] truncate min-w-0">
        <span class="font-bold text-ink">{@subj}</span>
        <span :if={@preview != ""} class="text-ink55"> -    {@preview}</span>
      </span>
      <span class="font-mono text-[11px] text-right whitespace-nowrap tabular-nums font-semibold text-ink">
        {@time}
      </span>
    </div>
    """
  end

  attr :drafting, :boolean, default: false
  attr :can_approve, :boolean, default: false

  defp action_bar(assigns) do
    ~H"""
    <div class="mt-8 pt-5 border-t border-ink20 flex items-center justify-end">
      <Liid.btn
        variant={:primary}
        phx-click="approve"
        disabled={@drafting or not @can_approve}
      >
        <Liid.icon name="check" size={12} /> Approve &amp; next
      </Liid.btn>
    </div>
    """
  end
end
