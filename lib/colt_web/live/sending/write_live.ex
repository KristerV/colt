defmodule ColtWeb.Sending.WriteLive do
  @moduledoc """
  The daily driver: one contact, one draft, approve / edit / reject.

  The contact you see is the next pending one. The AI drafts it in a variant
  it picks (the least-sent active variant — fair A/B rotation), shown in a
  quiet "Writing · Variant A" line. That line's dropdown is the only place
  variants surface: switch variant (redraws visibly) or "+ New variant" to
  branch the draft you're looking at into a fresh approach.

  A variant's shape (followup count + cadence) is set once, while writing its
  first (seed) contact — structure controls only appear then. Once a variant
  has been sent to anyone, its shape is locked and later contacts just show
  bodies to approve.

  States:
    · :loading   — picking next contact
    · :empty     — pool exhausted: nothing pending and nothing left to mint
    · :drafting  — contact loaded, EmailWriter still running
    · :default   — draft loaded; editor + Approve & next
  """

  use ColtWeb, :live_view

  alias Colt.Markets

  alias Colt.Resources.{
    Campaign,
    CampaignContact,
    EmailAccount,
    OutboundEmail,
    Sequence,
    SequenceStep,
    Thread
  }

  alias Colt.Services.Sending.{
    ApproveContact,
    AssignInbox,
    PromoteOne,
    RejectContactIcp,
    RejectContactPick
  }

  alias Colt.Services.Sending.EmailWriter
  alias Phoenix.PubSub
  alias ColtWeb.Components.{Funnel, Liid}

  @pubsub Colt.PubSub

  on_mount {ColtWeb.LiveUserAuth, :live_plan_required}
  on_mount {ColtWeb.Sending.PanicHook, :default}
  on_mount {ColtWeb.Sending.MarkInitializedHook, :default}

  defp languages, do: Markets.languages()

  defp admin?(user), do: Map.get(user, :is_admin) == true

  def mount(%{"id" => id} = params, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        ensure_first_variant(campaign, actor)
        variants = Sequence.list_for_campaign!(campaign.id, actor: actor)
        sequence = pick_variant(variants, params["variant_id"], campaign.id, actor)

        if connected?(socket), do: PubSub.subscribe(@pubsub, topic(campaign.id))

        socket =
          socket
          |> assign(
            page_title: gettext("Write — %{name}", name: campaign.name),
            campaign: campaign,
            variants: variants,
            sequence: sequence,
            selected_id: sequence.id,
            steps: sequence.sequence_steps,
            seeded?: seeded?(sequence.id, campaign.id, actor),
            drafts_sequence_id: sequence.id,
            state: :loading,
            contact: nil,
            person: nil,
            company: nil,
            sender: nil,
            drafts: [],
            email_steps: [],
            subject: "",
            bodies: %{},
            is_admin: admin?(actor),
            ooo_draft: nil,
            ooo_subject: "",
            first_email: false,
            saved_at: nil,
            learning_open?: false,
            learning_saving?: false,
            learning_error: nil
          )
          |> load_next_contact()

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  # Resolve which variant to write in: an explicit one, else the least-sent
  # active variant (fair A/B rotation; falls back to any if none active).
  defp pick_variant(variants, vid, campaign_id, actor) do
    chosen =
      (vid && Enum.find(variants, &(&1.id == vid))) ||
        least_sent_active(variants, campaign_id, actor)

    Sequence.get!(chosen.id, load: [:sequence_steps], actor: actor)
  end

  defp least_sent_active(variants, campaign_id, actor) do
    pool =
      case Enum.filter(variants, & &1.enabled) do
        [] -> variants
        active -> active
      end

    counts = sent_counts(campaign_id, actor)
    Enum.min_by(pool, &Map.get(counts, &1.id, 0))
  end

  # Contacts committed to each variant (sequence_id stamped at approval).
  defp sent_counts(campaign_id, actor) do
    case CampaignContact.list_for_campaign(campaign_id, actor: actor) do
      {:ok, contacts} ->
        contacts |> Enum.reject(&is_nil(&1.sequence_id)) |> Enum.frequencies_by(& &1.sequence_id)

      _ ->
        %{}
    end
  end

  # A variant is "seeded" (shape locked) once it's been sent to anyone.
  defp seeded?(sequence_id, campaign_id, actor) do
    Map.get(sent_counts(campaign_id, actor), sequence_id, 0) > 0
  end

  defp ensure_first_variant(campaign, actor) do
    case Sequence.list_for_campaign!(campaign.id, actor: actor) do
      [] ->
        {:ok, seq} = Sequence.create_named(campaign.id, gettext("Variant A"), actor: actor)
        Sequence.set_language(seq, Markets.language_for(campaign.market), actor: actor)

      _ ->
        :ok
    end
  end

  # ── Events ─────────────────────────────────────────────────────────────

  def handle_event("set_subject", %{"value" => v}, socket) do
    socket = persist_subject(socket, v)
    {:noreply, assign(socket, subject: v) |> mark_saved()}
  end

  def handle_event("set_body", %{"position" => pos, "value" => v}, socket) do
    pos = String.to_integer(pos)
    bodies = Map.put(socket.assigns.bodies, pos, v)
    socket = persist_body(socket, pos, v)
    {:noreply, assign(socket, bodies: bodies) |> mark_saved()}
  end

  # The admin-only OOO welcome-back keeps its own subject (independent of the
  # sequence-wide subject), so it has a dedicated event.
  def handle_event("set_ooo_subject", %{"value" => v}, socket) do
    actor = socket.assigns.current_user

    socket =
      case socket.assigns[:ooo_draft] do
        nil -> socket
        d -> assign(socket, ooo_draft: save_user_fields(d, v, d.user_body, actor))
      end

    {:noreply, socket |> assign(ooo_subject: v) |> mark_saved()}
  end

  # ── Variant picker (the quiet dropdown) ────────────────────────────────

  # The dropdown's last option is "+ new variant"; everything else is a switch.
  def handle_event("switch_variant", %{"variant_id" => "__new__"}, socket) do
    {:noreply, new_variant(socket)}
  end

  def handle_event("switch_variant", %{"variant_id" => id}, socket) do
    {:noreply, switch_to_variant(socket, id)}
  end

  # ── Variant structure: language + followups + timing + terminal ────────

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

    actor = socket.assigns.current_user

    with {:ok, step} <- SequenceStep.get(id, actor: actor),
         {:ok, _} <- SequenceStep.set_delay(step, days, actor: actor) do
      {:noreply, socket |> reload_structure() |> mark_saved()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_terminal_action", %{"step_id" => id, "value" => v}, socket) do
    action = if v == "call_ready", do: :call_ready, else: :no_reply
    actor = socket.assigns.current_user

    with {:ok, step} <- SequenceStep.get(id, actor: actor),
         {:ok, _} <- SequenceStep.set_terminal_action(step, action, actor: actor),
         {:ok, _} <- Sequence.bump_version(socket.assigns.sequence, actor: actor) do
      {:noreply, socket |> reload_structure() |> mark_saved()}
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

    if terminal, do: SequenceStep.set_position!(terminal, new_position + 1, actor: actor)

    {:ok, _} =
      SequenceStep.create(socket.assigns.sequence.id, new_position, :email, 2, actor: actor)

    {:ok, _} = Sequence.bump_version(socket.assigns.sequence, actor: actor)

    {:noreply, socket |> reload_structure() |> mark_saved()}
  end

  def handle_event("remove_step", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, step} <- SequenceStep.get(id, actor: actor),
         true <- step.kind == :email,
         true <- step.position > 0,
         :ok <- SequenceStep.delete_step(step, actor: actor) do
      reindex_email_steps(socket.assigns.sequence.id, actor)
      {:ok, _} = Sequence.bump_version(socket.assigns.sequence, actor: actor)
      {:noreply, socket |> reload_structure() |> mark_saved()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("approve", _params, socket) do
    actor = socket.assigns.current_user

    if Colt.Accounts.User.paid?(actor) do
      do_approve(socket)
    else
      {:noreply,
       put_flash(socket, :error, gettext("Your plan is inactive — pick a plan to send."))}
    end
  end

  # ── Skip contact: "Not a good fit" ─────────────────────────────────────

  def handle_event("open_learning", _params, socket) do
    {:noreply, assign(socket, learning_open?: true, learning_error: nil)}
  end

  def handle_event("close_learning", _params, socket) do
    {:noreply,
     assign(socket, learning_open?: false, learning_error: nil, learning_saving?: false)}
  end

  def handle_event("submit_learning", %{"reason" => reason} = params, socket) do
    reason = String.trim(reason || "")
    scope = if params["scope"] == "company", do: :company, else: :contact

    cond do
      socket.assigns.contact == nil ->
        {:noreply, socket}

      reason == "" ->
        {:noreply,
         assign(socket, learning_error: gettext("Tell us why so we can learn the rule."))}

      true ->
        send(self(), {:save_learning, scope, socket.assigns.contact.id, reason})
        {:noreply, assign(socket, learning_saving?: true, learning_error: nil)}
    end
  end

  defp do_approve(socket) do
    actor = socket.assigns.current_user
    contact = socket.assigns.contact

    edits = %{
      "subject" => socket.assigns.subject,
      "ooo_subject" => socket.assigns.ooo_subject,
      "bodies" => socket.assigns.bodies
    }

    case ApproveContact.run(contact.id, edits,
           sequence_id: socket.assigns.sequence.id,
           actor: actor
         ) do
      {:ok, _} ->
        {:noreply, load_next_contact(socket)}

      {:error, :no_healthy_inbox} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext(
             "No healthy sending inbox enrolled in this campaign. Add one under Sending accounts."
           )
         )}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Couldn't approve: %{reason}", reason: inspect(reason))
         )}
    end
  end

  defp learning_saved_flash(:company),
    do: gettext("Marked as ICP miss and removed from sending.")

  defp learning_saved_flash(:contact),
    do: gettext("Saved — we'll pick a better contact next time. Removed from sending.")

  def handle_info({:save_learning, scope, contact_id, reason}, socket) do
    actor = socket.assigns.current_user

    result =
      case scope do
        :company -> RejectContactIcp.run(contact_id, reason, actor: actor)
        :contact -> RejectContactPick.run(contact_id, reason, actor: actor)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(learning_open?: false, learning_saving?: false, learning_error: nil)
         |> put_flash(:info, learning_saved_flash(scope))
         |> load_next_contact()}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           learning_saving?: false,
           learning_error: gettext("Couldn't save that. Try again.")
         )}
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
       |> put_flash(:error, gettext("AI writer failed: %{reason}", reason: inspect(reason)))
       |> assign(state: :default)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Internals ──────────────────────────────────────────────────────────

  # Pull model: show the next pending contact; when there is none, mint one
  # from the enriched pool on demand (PromoteOne). The empty state appears
  # only when the pool itself is exhausted.
  defp load_next_contact(socket) do
    actor = socket.assigns.current_user
    campaign = socket.assigns.campaign

    case next_or_mint(campaign.id, actor) do
      {:ok, contact} ->
        contact =
          Ash.load!(contact, [person: [company: [:annual_reports]], thread: []],
            actor: actor,
            authorize?: true
          )

        socket
        |> assign(
          contact: contact,
          person: contact.person,
          company: contact.person && contact.person.company,
          seeded?: seeded?(socket.assigns.sequence.id, campaign.id, actor),
          subject: "",
          bodies: %{}
        )
        |> load_drafts_or_start_writer()

      :none ->
        assign(socket,
          state: :empty,
          contact: nil,
          drafts: [],
          subject: "",
          bodies: %{}
        )
    end
  end

  defp next_or_mint(campaign_id, actor) do
    case CampaignContact.next_pending(campaign_id, actor: actor) do
      {:ok, %CampaignContact{} = contact} ->
        {:ok, contact}

      _ ->
        case PromoteOne.run(campaign_id, actor: actor) do
          {:ok, %CampaignContact{} = contact} -> {:ok, contact}
          _ -> :none
        end
    end
  end

  # Switch the working variant. Same one → no-op. Otherwise regenerate the
  # current contact's draft under the new variant (clearing the old rows) so
  # one variant's content never shows under another.
  defp switch_to_variant(socket, vid) do
    if vid == socket.assigns.selected_id do
      socket
    else
      actor = socket.assigns.current_user
      campaign = socket.assigns.campaign
      sequence = Sequence.get!(vid, load: [:sequence_steps], actor: actor)

      socket =
        assign(socket,
          sequence: sequence,
          selected_id: vid,
          steps: sequence.sequence_steps,
          seeded?: seeded?(vid, campaign.id, actor)
        )

      case socket.assigns.contact do
        nil -> assign(socket, email_steps: email_steps(socket))
        contact -> socket |> tap_clear_drafts(contact, actor) |> load_drafts_or_start_writer()
      end
    end
  end

  defp tap_clear_drafts(socket, contact, actor) do
    clear_drafts(contact, actor)
    socket
  end

  # Clone the current variant's shape into a fresh variant and carry the draft
  # we're looking at into it (the original is untouched) — for when you've
  # written something and realize it's its own approach.
  defp new_variant(socket) do
    actor = socket.assigns.current_user
    campaign = socket.assigns.campaign
    source = socket.assigns.sequence
    name = variant_name(length(socket.assigns.variants))

    {:ok, created} = Sequence.create_bare(campaign.id, name, source.language, actor: actor)
    copy_steps(source.sequence_steps, created.id, actor)
    sequence = Sequence.get!(created.id, load: [:sequence_steps], actor: actor)

    email_steps =
      sequence.sequence_steps |> Enum.filter(&(&1.kind == :email)) |> Enum.sort_by(& &1.position)

    # Keep the current draft rows in place — the content carries over. The new
    # variant has no contacts yet, so it's unseeded (shape still editable).
    socket
    |> assign(
      sequence: sequence,
      selected_id: sequence.id,
      steps: sequence.sequence_steps,
      email_steps: email_steps,
      seeded?: false,
      drafts_sequence_id: sequence.id,
      variants: Sequence.list_for_campaign!(campaign.id, actor: actor)
    )
    |> mark_saved()
  end

  # A=0, B=1, … then fall back to numbered.
  defp variant_name(index) when index < 26,
    do: gettext("Variant %{l}", l: <<65 + index::utf8>>)

  defp variant_name(index), do: gettext("Variant %{n}", n: index + 1)

  defp clear_drafts(%{thread: %{id: tid}}, actor) do
    OutboundEmail.list_for_thread!(tid, actor: actor, authorize?: actor != nil)
    |> Enum.filter(&(&1.status == :drafted))
    |> Enum.each(&Ash.destroy!(&1, actor: actor, authorize?: actor != nil))
  end

  defp clear_drafts(_, _), do: :ok

  defp copy_steps(steps, new_sequence_id, actor) do
    Enum.each(steps, fn s ->
      Ash.create!(
        SequenceStep,
        %{
          sequence_id: new_sequence_id,
          position: s.position,
          kind: s.kind,
          delay_days: s.delay_days,
          terminal_action: s.terminal_action
        },
        action: :create,
        actor: actor,
        authorize?: actor != nil
      )
    end)
  end

  defp load_drafts_or_start_writer(socket) do
    # Pick the sticky sender now — before the writer runs and before the user
    # hand-writes the first email — so the chosen account is visible in the
    # editor and the writer composes in its name. ApproveContact reuses it.
    socket = ensure_sender_assigned(socket)
    socket = ensure_ooo_step(socket)
    socket = assign(socket, drafts_sequence_id: socket.assigns.sequence.id)
    actor = socket.assigns.current_user
    contact = socket.assigns.contact

    email_steps = email_steps(socket)
    wanted = Enum.map(email_steps, & &1.position) ++ ooo_wanted(socket)
    drafts = reconcile_drafts(contact, wanted, actor)
    missing = wanted -- Enum.map(drafts, & &1.step_position)
    socket = assign(socket, email_steps: email_steps)

    cond do
      missing == [] ->
        socket
        |> assign(state: :default, first_email: empty_pool?(socket))
        |> put_drafts(drafts)

      # Empty template pool: the user writes the first sequence under this
      # template by hand. Seed blank drafts and skip the AI writer so their
      # own wording becomes this template's example pool.
      empty_pool?(socket) ->
        seed_blank_drafts(socket, missing)

      true ->
        kick_off_writer(socket)

        socket
        |> assign(state: :drafting, first_email: false)
        |> put_drafts(drafts)
    end
  end

  # Admin-only: ensure this variant carries an OOO welcome-back step (position
  # -1). Created blank; the admin authors it in the golden card. Sequences
  # without it (all non-admin) are completely unaffected.
  defp ensure_ooo_step(socket) do
    if socket.assigns[:is_admin] and not Enum.any?(socket.assigns.steps, &(&1.kind == :ooo)) do
      actor = socket.assigns.current_user

      SequenceStep.create!(socket.assigns.sequence.id, SequenceStep.ooo_position(), :ooo, 0,
        actor: actor
      )

      sequence = Sequence.get!(socket.assigns.sequence.id, load: [:sequence_steps], actor: actor)
      assign(socket, sequence: sequence, steps: sequence.sequence_steps)
    else
      socket
    end
  end

  # The OOO draft position to reconcile/seed — only for admins on a variant
  # that actually has the step. Empty list ⇒ the -1 row is never seeded/kept.
  defp ooo_wanted(socket) do
    if socket.assigns[:is_admin] and Enum.any?(socket.assigns.steps, &(&1.kind == :ooo)),
      do: [SequenceStep.ooo_position()],
      else: []
  end

  # Split the thread's rows into the linear email drafts (rendered + required
  # for approval) and the optional admin OOO welcome-back draft (position -1),
  # then seed the editor inputs from both.
  defp put_drafts(socket, all_drafts) do
    {ooo, emails} =
      Enum.split_with(all_drafts, &(&1.step_position == SequenceStep.ooo_position()))

    socket
    |> assign(drafts: emails, ooo_draft: List.first(ooo))
    |> seed_inputs_from_drafts(emails, List.first(ooo))
  end

  # No user-edited emails written under this template yet ⇒ write by hand.
  defp empty_pool?(socket) do
    case OutboundEmail.list_user_edited_for_sequence(socket.assigns.sequence.id, 1,
           actor: socket.assigns.current_user
         ) do
      {:ok, []} -> true
      _ -> false
    end
  end

  # Create empty :drafted rows for the missing email steps so the editor
  # renders the full sequence with blank fields, ready for the user to type.
  defp seed_blank_drafts(socket, missing_positions) do
    actor = socket.assigns.current_user
    contact = socket.assigns.contact
    thread = ensure_thread(contact, actor)
    seed = EmailWriter.starter_body(socket.assigns.sender)

    Enum.each(missing_positions, fn pos ->
      OutboundEmail.create_draft!(thread.id, pos, nil, seed,
        actor: actor,
        authorize?: actor != nil
      )
    end)

    contact = %{contact | thread: thread}
    drafts = list_outbound_drafts(contact, actor)

    socket
    |> assign(contact: contact, state: :default, first_email: true)
    |> put_drafts(drafts)
  end

  defp ensure_thread(%{thread: %Thread{} = thread}, _actor), do: thread

  defp ensure_thread(contact, actor),
    do: Thread.create_for_contact!(contact.id, actor: actor, authorize?: actor != nil)

  defp email_steps(socket) do
    socket.assigns.steps
    |> Enum.filter(&(&1.kind == :email))
    |> Enum.sort_by(& &1.position)
  end

  # After a structural change: reload the template's steps, then make the
  # contact's drafts match (drop drafts at removed positions, seed blanks at
  # new ones) so the editor renders the full sequence.
  defp reload_structure(socket) do
    actor = socket.assigns.current_user
    sequence = Sequence.get!(socket.assigns.sequence.id, load: [:sequence_steps], actor: actor)
    socket = assign(socket, sequence: sequence, steps: sequence.sequence_steps)
    email_steps = email_steps(socket)
    socket = assign(socket, email_steps: email_steps)
    contact = socket.assigns.contact

    if contact do
      wanted = Enum.map(email_steps, & &1.position) ++ ooo_wanted(socket)
      drafts = reconcile_drafts(contact, wanted, actor)
      missing = wanted -- Enum.map(drafts, & &1.step_position)

      contact =
        if missing == [], do: contact, else: %{contact | thread: ensure_thread(contact, actor)}

      # In first-email (hand-written) mode, seed new steps with the signature
      # too, matching seed_blank_drafts/2.
      seed = if socket.assigns[:first_email], do: EmailWriter.starter_body(socket.assigns.sender)

      Enum.each(missing, fn pos ->
        OutboundEmail.create_draft!(contact.thread.id, pos, nil, seed,
          actor: actor,
          authorize?: actor != nil
        )
      end)

      drafts = list_outbound_drafts(contact, actor)
      socket |> assign(contact: contact) |> put_drafts(drafts)
    else
      socket
    end
  end

  defp reindex_email_steps(sequence_id, actor) do
    steps =
      case SequenceStep.list_for_sequence(sequence_id, authorize?: false) do
        {:ok, list} -> list
        _ -> []
      end

    email_steps = Enum.filter(steps, &(&1.kind == :email))
    terminal = Enum.find(steps, &(&1.kind == :terminal))

    email_steps
    |> Enum.with_index()
    |> Enum.each(fn {step, idx} ->
      if step.position != idx, do: SequenceStep.set_position!(step, idx, actor: actor)
    end)

    if terminal && terminal.position != length(email_steps),
      do: SequenceStep.set_position!(terminal, length(email_steps), actor: actor)
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
    socket |> assign(state: :default) |> put_drafts(drafts)
  end

  defp list_outbound_drafts(%{thread: %{id: tid}}, actor) do
    OutboundEmail.list_for_thread!(tid, actor: actor, authorize?: actor != nil)
    |> Enum.sort_by(& &1.step_position)
  end

  defp list_outbound_drafts(_, _), do: []

  defp seed_inputs_from_drafts(socket, drafts, ooo_draft) do
    first = List.first(drafts)
    subject = (first && (first.user_subject || first.ai_subject)) || ""

    rows = drafts ++ List.wrap(ooo_draft)

    bodies =
      Enum.into(rows, %{}, fn e ->
        {e.step_position, e.user_body || e.ai_body || ""}
      end)

    ooo_subject = (ooo_draft && (ooo_draft.user_subject || ooo_draft.ai_subject)) || ""

    assign(socket, subject: subject, bodies: bodies, ooo_subject: ooo_subject)
  end

  defp kick_off_writer(socket) do
    parent = self()
    contact_id = socket.assigns.contact.id
    sequence_id = socket.assigns.sequence.id
    actor = socket.assigns.current_user

    Task.start(fn ->
      case EmailWriter.run(contact_id, sequence_id: sequence_id, actor: actor) do
        {:ok, _} -> send(parent, {:drafts_ready, contact_id})
        {:error, reason} -> send(parent, {:drafts_failed, contact_id, reason})
      end
    end)
  end

  # Assign the sticky sender once, when the contact enters the writing view.
  # Reuses an existing assignment (sticky across revisits); best-effort — with
  # no healthy inbox we leave it nil and the views fall back gracefully.
  defp ensure_sender_assigned(socket) do
    actor = socket.assigns.current_user
    contact = socket.assigns.contact

    {contact, sender} =
      case contact.assigned_email_account_id do
        id when is_binary(id) ->
          {contact, load_account(id, actor)}

        _ ->
          case AssignInbox.run(contact.campaign_id, actor: actor) do
            {:ok, inbox} ->
              case CampaignContact.assign_inbox(contact, inbox.id, actor: actor) do
                {:ok, updated} -> {updated, inbox}
                _ -> {contact, nil}
              end

            _ ->
              {contact, nil}
          end
      end

    assign(socket, contact: contact, sender: sender)
  end

  defp load_account(id, actor) do
    case EmailAccount.get(id, actor: actor) do
      {:ok, account} -> account
      _ -> nil
    end
  end

  # Subject is shared across the whole sequence, so persist it onto every draft
  # (mirrors how ApproveContact applies edits).
  defp persist_subject(socket, v) do
    actor = socket.assigns.current_user

    drafts =
      Enum.map(socket.assigns.drafts, fn email ->
        save_user_fields(email, v, email.user_body, actor)
      end)

    assign(socket, drafts: drafts)
  end

  defp persist_body(socket, pos, v) do
    actor = socket.assigns.current_user

    if pos == SequenceStep.ooo_position() do
      case socket.assigns[:ooo_draft] do
        nil -> socket
        d -> assign(socket, ooo_draft: save_user_fields(d, d.user_subject, v, actor))
      end
    else
      drafts =
        Enum.map(socket.assigns.drafts, fn email ->
          if email.step_position == pos do
            save_user_fields(email, email.user_subject, v, actor)
          else
            email
          end
        end)

      assign(socket, drafts: drafts)
    end
  end

  defp save_user_fields(email, user_subject, user_body, actor) do
    case OutboundEmail.update_user_fields(email, user_subject, user_body,
           actor: actor,
           authorize?: actor != nil
         ) do
      {:ok, updated} -> updated
      {:error, _} -> email
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
      active={:write}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="w-full max-w-[640px] mx-auto md:px-6 py-6">
        <%= case @state do %>
          <% :loading -> %>
            <div class="text-[12px] text-inkFaint">{gettext("loading…")}</div>
          <% :empty -> %>
            <.empty_state />
          <% s when s in [:default, :drafting] -> %>
            <.contact_header person={@person} company={@company} />
            <.variant_bar variants={@variants} selected_id={@selected_id} />
            <.editor
              sender={@sender}
              drafts={@drafts}
              email_steps={@email_steps}
              terminal={Enum.find(@steps, &(&1.kind == :terminal))}
              language={@sequence.language}
              subject={@subject}
              bodies={@bodies}
              drafting={s == :drafting}
              seeded={@seeded?}
              first_email={@first_email}
              saved_at={@saved_at}
              is_admin={@is_admin}
              ooo_draft={@ooo_draft}
              ooo_subject={@ooo_subject}
            />
            <.action_bar
              drafting={s == :drafting}
              can_approve={can_approve?(@subject, @bodies, @drafts)}
            />
        <% end %>
      </div>

      <Funnel.learning_modal
        :if={@learning_open? && @company}
        row={%{name: @company.name}}
        mode={:reject}
        saving?={@learning_saving?}
        error={@learning_error}
        note={
          gettext(
            "Tell us why in your own words, then pick which it is. Wrong contact teaches the picker who to choose; wrong company adds an ICP rule. Either way this contact drops from sending."
          )
        }
      />
    </Layouts.app>
    """
  end

  attr :variants, :list, required: true
  attr :selected_id, :string, required: true

  defp variant_bar(assigns) do
    ~H"""
    <div class="mt-5 flex items-center gap-2.5 text-[11px]">
      <span class="text-[10.5px] tracking-[0.09em] uppercase text-inkFaint font-semibold">
        {gettext("Variant")}
      </span>
      <form phx-change="switch_variant" class="inline-flex">
        <select
          name="variant_id"
          class="px-3 py-1.5 border border-border bg-card text-[12px] text-ink rounded-[8px] outline-none cursor-pointer focus:border-accentRing"
        >
          <option :for={v <- @variants} value={v.id} selected={v.id == @selected_id}>
            {v.name}
          </option>
          <option value="__new__">{gettext("+ new variant")}</option>
        </select>
      </form>
    </div>
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

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center text-center gap-6 py-10">
      <div class="text-[80px] font-bold leading-none text-ink20">0</div>
      <h2 class="text-[30px] font-semibold tracking-[-0.02em] leading-[1.1] m-0 max-w-[520px]">
        {raw(gettext("All caught <em>up</em>."))}
      </h2>
      <p class="text-[14px] text-inkSoft max-w-[460px] leading-[1.6]">
        {gettext(
          "Every enriched contact has been brought into sending. New ones appear here as enrichment finds them."
        )}
      </p>
    </div>
    """
  end

  attr :sender, :map, default: nil
  attr :drafts, :list, required: true
  attr :email_steps, :list, default: []
  attr :terminal, :map, default: nil
  attr :language, :string, default: "en"
  attr :subject, :string, required: true
  attr :bodies, :map, required: true
  attr :drafting, :boolean, default: false
  attr :seeded, :boolean, default: false
  attr :first_email, :boolean, default: false
  attr :saved_at, :any, default: nil
  attr :is_admin, :boolean, default: false
  attr :ooo_draft, :map, default: nil
  attr :ooo_subject, :string, default: ""

  defp editor(assigns) do
    step_by_position = Map.new(assigns.email_steps, fn s -> {s.position, s} end)

    assigns = assign(assigns, :step_by_position, step_by_position)

    ~H"""
    <div class="mt-5 flex items-center gap-2 text-[11px]">
      <span class="text-[10.5px] tracking-[0.09em] uppercase text-inkFaint font-semibold">
        {gettext("Sending as")}
      </span>
      <%= if @sender do %>
        <span class="text-ink font-medium">{sender_display_or_local(@sender)}</span>
        <span class="text-inkFaint">&lt;{@sender.address}&gt;</span>
      <% else %>
        <span class="text-inkFaint">
          {gettext("no inbox available — connect one under Sending accounts")}
        </span>
      <% end %>
    </div>

    <%= if @drafting do %>
      <.generating_notice />
    <% else %>
      <div class="mt-5 flex items-center gap-2.5 text-[11px]">
        <span class="text-[10.5px] tracking-[0.09em] uppercase text-inkFaint font-semibold">
          {gettext("Language")}
        </span>
        <form phx-change="set_language" class="inline-flex">
          <select
            name="language"
            class="px-3 py-1.5 border border-border bg-card text-[12px] text-ink rounded-[8px] outline-none cursor-pointer focus:border-accentRing"
          >
            <option :for={{code, label} <- languages()} value={code} selected={@language == code}>
              {label}
            </option>
          </select>
        </form>
      </div>
      <div
        :if={@first_email}
        class="mt-5 px-4 py-3 border border-accentRing bg-accentSoft rounded-[11px] text-[12.5px] leading-[1.55] text-inkSoft"
      >
        {gettext(
          "Write this first sequence yourself. The AI writer stays out of the way until you've sent one — then it learns your voice from it and drafts the rest."
        )}
      </div>

      <div class="mt-5 text-[10.5px] tracking-[0.09em] uppercase text-inkFaint font-semibold">
        {gettext("Subject")}
      </div>
      <form id="subject-form" phx-change="set_subject" class="block mt-2.5">
        <input
          type="text"
          id="subject-input"
          name="value"
          value={@subject}
          phx-debounce="400"
          placeholder={gettext("subject line")}
          class="w-full px-4 py-2.5 border border-border bg-bgSoft rounded-[8px] text-[13.5px] text-ink outline-none placeholder:text-inkFaint focus:border-accentRing focus:bg-card"
        />
      </form>

      <div class="mt-5 flex flex-col gap-5">
        <%= for {email, idx} <- Enum.with_index(@drafts) do %>
          <% step = Map.get(@step_by_position, email.step_position) %>
          <.wait_edit
            :if={idx > 0}
            days={(step && step.delay_days) || 2}
            id={step && step.id}
            terminal={false}
            editable={not @seeded}
          />
          <.step_card
            email={email}
            idx={idx}
            step_id={step && step.id}
            removable={not @seeded}
            body={Map.get(@bodies, email.step_position, email.user_body || email.ai_body || "")}
            disabled={false}
          />
        <% end %>

        <button
          :if={not @seeded}
          type="button"
          phx-click="add_step"
          class="py-3 border border-dashed border-borderStrong text-inkSoft text-[12px] font-medium rounded-[11px] cursor-pointer hover:border-accentRing hover:text-accent hover:bg-accentSoft transition-colors"
        >
          {gettext("+ add follow-up")}
        </button>

        <%= if @terminal do %>
          <.wait_edit
            days={@terminal.delay_days}
            id={@terminal.id}
            terminal={true}
            editable={not @seeded}
          />
          <.terminal_block step={@terminal} editable={not @seeded} />
        <% end %>

        <div :if={@is_admin && @ooo_draft}>
          <.ooo_card
            ooo_draft={@ooo_draft}
            subject={@ooo_subject}
            body={Map.get(@bodies, -1, "")}
          />
        </div>
      </div>

      <div :if={@saved_at} class="mt-6 text-[11px] text-inkFaint tabular-nums">
        {gettext("saved %{at}", at: Calendar.strftime(@saved_at, "%H:%M:%S"))}
      </div>
    <% end %>
    """
  end

  defp generating_notice(assigns) do
    ~H"""
    <div class="mt-10 flex items-center gap-2.5 text-[12px] text-inkSoft">
      <span class="relative w-[7px] h-[7px] shrink-0">
        <span class="absolute inset-0 rounded-full bg-accent" />
        <span class="absolute -inset-[3px] rounded-full bg-accent opacity-40 animate-[pulse-halo_1.8s_ease-out_infinite]" />
      </span>
      {gettext("generating sequence…")}
    </div>
    """
  end

  # Human label for the sending inbox — the first line of the signature if set,
  # else the email's local-part humanized (matches the writer's own fallback).
  defp sender_display(%{display_name: sig}) when is_binary(sig) do
    sig |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.find(&(&1 != ""))
  end

  defp sender_display(_), do: nil

  defp sender_display_or_local(%{address: address} = sender),
    do: sender_display(sender) || humanize_local_part(address)

  defp sender_display_or_local(_), do: nil

  defp humanize_local_part(address) when is_binary(address) do
    address
    |> String.split("@")
    |> List.first()
    |> String.split(~r/[._]/)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp humanize_local_part(_), do: nil

  attr :person, :map, required: true
  attr :company, :map, default: nil

  defp contact_header(assigns) do
    assigns =
      assigns
      |> assign(:reports, recent_reports(assigns[:company]))
      |> assign(:registry_link, Colt.CompanyRegistry.link(assigns[:company]))

    ~H"""
    <div class="p-5 border border-border bg-card rounded-[11px]" style="box-shadow:var(--shadow)">
      <div
        :if={@company && @company.status != :registered}
        class={[
          "mb-3 text-[10px] tracking-[0.06em] uppercase font-semibold rounded-[8px] px-2 py-1 border inline-block",
          (@company.status == :other && "text-amber border-amber/30 bg-amberSoft") ||
            "text-red border-red/30 bg-redSoft"
        ]}
      >
        ⚠ {status_label(@company.status)}
      </div>
      <div class="flex flex-col sm:flex-row sm:items-baseline sm:justify-between gap-4">
        <div>
          <div class="text-[24px] font-bold tracking-[-0.02em] leading-none text-ink">
            {(@person && @person.name) || "—"}
          </div>
          <div class="mt-1.5 text-[13px] text-inkSoft">
            {(@person && @person.title) || "—"}
          </div>
          <div class="mt-1 text-[11.5px] text-accent font-medium">
            {(@person && @person.email) || ""}
          </div>
        </div>
        <div :if={@company} class="text-left sm:text-right">
          <div class="text-[14px] font-semibold text-ink">{@company.name}</div>
          <div class="text-[10px] tracking-[0.06em] uppercase text-inkFaint font-semibold mt-0.5">
            {[
              @company.industry_code,
              @company.employees_latest && "#{@company.employees_latest} emp"
            ]
            |> Enum.reject(&(&1 in [nil, ""]))
            |> Enum.join(" · ")}
          </div>
          <a
            :if={@company.website_url}
            href={href_url(@company.website_url)}
            target="_blank"
            rel="noopener noreferrer"
            class="inline-block mt-1 text-[11px] text-accent font-medium hover:underline"
          >
            ↗ {display_host(@company.website_url)}
          </a>
          <a
            :if={@registry_link}
            href={@registry_link.url}
            target="_blank"
            rel="noopener noreferrer"
            class="block mt-1 text-[11px] text-inkFaint hover:text-accent hover:underline"
          >
            ↗ {@registry_link.label} {@company.registry_code}
          </a>
        </div>
      </div>
      <div
        :if={@company && @company.ai_summary}
        class="mt-3.5 text-[13px] leading-[1.55] text-inkSoft border-t border-border pt-3.5"
      >
        {@company.ai_summary}
      </div>
      <div :if={@reports != []} class="mt-3.5 border-t border-border pt-3.5">
        <table class="w-full text-[11.5px] tabular-nums">
          <thead>
            <tr class="text-inkFaint text-[9px] tracking-[0.08em] uppercase font-semibold">
              <th class="text-left font-semibold pb-1">{gettext("Year")}</th>
              <th class="text-right font-semibold pb-1">{gettext("Revenue")}</th>
              <th class="text-right font-semibold pb-1 pl-2"></th>
              <th class="text-right font-semibold pb-1 pl-3">{gettext("Employees")}</th>
              <th class="text-right font-semibold pb-1 pl-2"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={r <- @reports} class="text-inkSoft">
              <td class="text-left py-0.5 text-ink">{r.year}</td>
              <td class="text-right py-0.5">{format_eur(r.revenue)}</td>
              <td class="text-right py-0.5 pl-2"><.delta_badge value={r.rev_delta} suffix="%" /></td>
              <td class="text-right py-0.5 pl-3">{r.employees || "—"}</td>
              <td class="text-right py-0.5 pl-2"><.delta_badge value={r.emp_delta} suffix="%" /></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :value, :any, required: true
  attr :suffix, :string, default: ""

  defp delta_badge(assigns) do
    ~H"""
    <span
      :if={@value not in [nil, 0]}
      class={["text-[9px] ml-1 font-medium", (@value > 0 && "text-accent") || "text-red"]}
    >
      {(@value > 0 && "▲") || "▼"}{abs(@value)}{@suffix}
    </span>
    """
  end

  # Latest 3 annual reports, newest first, each with a delta against the next older year.
  defp recent_reports(%{annual_reports: reports}) when is_list(reports) do
    sorted = Enum.sort_by(reports, & &1.year, :desc)

    sorted
    |> Enum.with_index()
    |> Enum.map(fn {r, i} ->
      prev = Enum.at(sorted, i + 1)

      %{
        year: r.year,
        revenue: r.revenue_eur,
        employees: r.employees,
        rev_delta: pct_delta(r.revenue_eur, prev && prev.revenue_eur),
        emp_delta: pct_delta(r.employees, prev && prev.employees)
      }
    end)
    |> Enum.take(3)
  end

  defp recent_reports(_), do: []

  defp pct_delta(nil, _), do: nil
  defp pct_delta(_, nil), do: nil

  defp pct_delta(cur, prev) do
    prev_f = to_float(prev)
    if prev_f == 0.0, do: nil, else: round((to_float(cur) - prev_f) / prev_f * 100)
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n / 1

  defp format_eur(nil), do: "—"

  defp format_eur(d) do
    n = Decimal.to_float(d)

    cond do
      n >= 1_000_000 -> "€#{trim_decimal(n / 1_000_000)}M"
      n >= 1_000 -> "€#{trim_decimal(n / 1_000)}K"
      true -> "€#{round(n)}"
    end
  end

  defp trim_decimal(x) do
    x |> Float.round(1) |> :erlang.float_to_binary(decimals: 1) |> String.replace_suffix(".0", "")
  end

  defp status_label(:liquidation), do: gettext("In liquidation")
  defp status_label(:deleted), do: gettext("Deleted from registry")
  defp status_label(_), do: gettext("Inactive")

  defp href_url("http" <> _ = url), do: url
  defp href_url(url), do: "https://" <> url

  defp display_host(url) do
    url
    |> String.replace(~r{^https?://}i, "")
    |> String.replace(~r{/.*$}, "")
    |> String.replace_prefix("www.", "")
  end

  attr :days, :integer, required: true
  attr :id, :any, required: true
  attr :terminal, :boolean, default: false
  attr :editable, :boolean, default: true

  defp wait_edit(assigns) do
    ~H"""
    <div class="relative pl-8 flex items-center -my-1">
      <span class="absolute left-[14px] top-0 bottom-0 w-px bg-border" />
      <span class="absolute left-[9px] top-[calc(50%-5px)] w-[11px] h-[11px] rounded-full bg-card border border-border" />
      <span class="text-[11.5px] text-inkSoft inline-flex items-center gap-2">
        {gettext("wait")}
        <%= if @editable do %>
          <form id={"delay-form-#{@id}"} phx-change="set_delay" class="inline-flex">
            <input type="hidden" name="step_id" value={@id} />
            <input
              type="number"
              id={"delay-input-#{@id}"}
              name="value"
              value={@days}
              min="0"
              phx-debounce="400"
              class="w-[52px] px-1.5 py-1 border border-border rounded-[8px] text-[12px] text-center bg-card text-ink tabular-nums outline-none focus:border-accentRing"
            />
          </form>
        <% else %>
          <span class="text-ink tabular-nums font-medium">{@days}</span>
        <% end %>
        {gettext("days")}
        <span :if={@terminal} class="text-[11px] text-inkFaint">
          {gettext("· then")}
        </span>
      </span>
    </div>
    """
  end

  attr :step, :map, required: true
  attr :editable, :boolean, default: true

  defp terminal_block(assigns) do
    ~H"""
    <div class="border border-dashed border-borderStrong rounded-[11px] bg-paperAlt px-[18px] py-4 flex flex-wrap items-center gap-3.5">
      <span class="inline-flex items-center justify-center w-[22px] h-[22px] rounded-full border border-inkFaint text-inkSoft text-[11px] font-semibold">
        ×
      </span>
      <span class="text-[13px] text-inkSoft">{gettext("If still no reply, mark contact as")}</span>
      <%= if @editable do %>
        <form id={"terminal-form-#{@step.id}"} phx-change="set_terminal_action" class="inline-flex">
          <input type="hidden" name="step_id" value={@step.id} />
          <select
            name="value"
            class="px-3 py-1.5 border border-border bg-card text-[12px] text-ink rounded-[8px] outline-none cursor-pointer focus:border-accentRing"
          >
            <option value="no_reply" selected={@step.terminal_action in [nil, :no_reply]}>
              no_reply
            </option>
            <option value="call_ready" selected={@step.terminal_action == :call_ready}>
              call_ready
            </option>
          </select>
        </form>
      <% else %>
        <span class="text-[12px] text-ink font-medium">{@step.terminal_action || :no_reply}</span>
      <% end %>
      <span class="flex-1" />
      <span class="text-[10px] tracking-[0.06em] uppercase text-inkFaint font-semibold">
        {gettext("end of sequence")}
      </span>
    </div>
    """
  end

  attr :email, :map, required: true
  attr :idx, :integer, required: true
  attr :step_id, :any, default: nil
  attr :removable, :boolean, default: true
  attr :body, :string, default: ""
  attr :disabled, :boolean, default: false

  defp step_card(assigns) do
    ~H"""
    <div
      id={"step-card-#{@email.step_position}"}
      class={[
        "rounded-[11px] bg-card border overflow-hidden",
        if(@idx == 0, do: "border-accentRing", else: "border-border")
      ]}
      style={"box-shadow:var(--shadow)#{if @idx == 0, do: ";box-shadow:0 0 0 1px var(--accentRing), var(--shadow)", else: ""}"}
    >
      <div class={[
        "flex items-center gap-3.5 px-5 py-3 border-b",
        if(@idx == 0, do: "bg-accentSoft border-[#dbe7fa]", else: "bg-bgSoft border-border")
      ]}>
        <span class={[
          "text-[13px] font-semibold",
          if(@idx == 0, do: "text-accent", else: "text-ink")
        ]}>
          {if @idx == 0, do: gettext("First email"), else: gettext("Follow-up %{n}", n: @idx)}
        </span>
        <span class="flex-1" />
        <button
          :if={@removable && @idx > 0 && @step_id}
          type="button"
          phx-click="remove_step"
          phx-value-id={@step_id}
          class="text-inkFaint hover:text-red cursor-pointer"
          aria-label={gettext("Remove follow-up")}
        >
          <Liid.icon name="x" size={12} />
        </button>
      </div>
      <form id={"body-form-#{@email.step_position}"} phx-change="set_body" class="block">
        <input type="hidden" name="position" value={@email.step_position} />
        <textarea
          id={"body-input-#{@email.step_position}"}
          name="value"
          rows="6"
          phx-debounce="600"
          disabled={@disabled}
          class="w-full px-5 py-4 bg-card text-[13.5px] leading-[1.6] text-inkSoft outline-none border-0 resize-none block"
          style="field-sizing: content;"
        >{@body}</textarea>
      </form>
    </div>
    """
  end

  attr :ooo_draft, :map, required: true
  attr :subject, :string, default: ""
  attr :body, :string, default: ""

  # Golden, admin-only card for the OOO welcome-back. Rendered after the
  # follow-ups; its blank body is optional (empty ⇒ the feature no-ops for the
  # contact). Kept out of @drafts so it never blocks approval.
  defp ooo_card(assigns) do
    ~H"""
    <div class="rounded-[11px] border border-gold/40 bg-goldSoft overflow-hidden [box-shadow:var(--shadow)]">
      <div class="flex items-center gap-3 px-5 py-3 border-b border-gold/30">
        <Liid.admin_badge label={gettext("Admin · Welcome-back")} />
        <span class="flex-1" />
        <span class="text-[10px] tracking-[0.06em] uppercase text-gold font-semibold">
          {gettext("out-of-office only")}
        </span>
      </div>
      <div class="px-5 py-4 flex flex-col gap-3 bg-card">
        <p class="text-[12px] leading-[1.5] text-inkSoft m-0">
          {gettext(
            "Sent only when a prospect auto-replies out-of-office: it welcomes them back ~3 days after they return, then the follow-ups resume. Leave blank to skip."
          )}
        </p>
        <form phx-change="set_ooo_subject" class="block">
          <input
            type="text"
            name="value"
            value={@subject}
            phx-debounce="400"
            placeholder={gettext("welcome-back subject")}
            class="w-full px-4 py-2.5 border border-border bg-bgSoft rounded-[8px] text-[13.5px] text-ink outline-none placeholder:text-inkFaint focus:border-accentRing focus:bg-card"
          />
        </form>
        <form id="ooo-body-form" phx-change="set_body" class="block">
          <input type="hidden" name="position" value={SequenceStep.ooo_position()} />
          <textarea
            id="ooo-body-input"
            name="value"
            rows="7"
            phx-debounce="600"
            placeholder={gettext("welcome them back, ask one light question…")}
            class="w-full px-4 py-3 border border-border bg-bgSoft rounded-[8px] text-[13.5px] leading-[1.6] text-ink outline-none resize-y placeholder:text-inkFaint focus:border-accentRing focus:bg-card"
          >{@body}</textarea>
        </form>
      </div>
    </div>
    """
  end

  attr :drafting, :boolean, default: false
  attr :can_approve, :boolean, default: false

  defp action_bar(assigns) do
    ~H"""
    <div class="mt-8 flex flex-wrap items-center justify-end gap-3">
      <button
        type="button"
        phx-click="open_learning"
        class="inline-flex items-center gap-1.5 px-3 py-[7px] text-[12px] font-semibold text-inkSoft border border-borderStrong rounded-[8px] hover:text-red hover:border-red/40 hover:bg-redSoft cursor-pointer bg-card"
      >
        <Liid.icon name="x" size={11} /> {gettext("Not a good fit")}
      </button>

      <Liid.btn
        variant={:primary}
        phx-click="approve"
        disabled={@drafting or not @can_approve}
      >
        <Liid.icon name="check" size={12} /> {gettext("Approve & next")}
      </Liid.btn>
    </div>
    """
  end
end
