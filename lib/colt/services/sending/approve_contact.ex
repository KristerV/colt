defmodule Colt.Services.Sending.ApproveContact do
  @moduledoc """
  Move one CampaignContact from :pending_approval → :approved.

  Steps (run/2):
    1. Load contact + sequence + draft emails.
    2. Apply pending user edits (subject, body per step).
    3. Pick sticky inbox.
    4. Snapshot the current sequence (steps + delays + terminal).
    5. Update the contact: status, assigned_email_account, snapshot, version.
    6. Schedule step 1's Email (naive: `scheduled_at = now` snapped into
       Mon–Fri 09:00–17:00 in UTC; followups stay :drafted until E5 sends
       step 1 and computes their slot).
    7. Mark the rest of the email drafts as :approved (no scheduled_at yet).
    8. Bump campaign.auto_approve_streak iff clean (no edits at all).
  """

  alias Colt.Resources.{Campaign, CampaignContact, Email, Sequence}
  alias Colt.Services.Sending.AssignInbox

  def run(contact_id, edits, opts \\ []) when is_binary(contact_id) and is_map(edits) do
    actor = Keyword.get(opts, :actor)

    with {:ok, contact} <- load_contact(contact_id, actor),
         {:ok, sequence} <- load_sequence(contact.campaign_id, actor),
         {:ok, drafts} <- load_drafts(contact, actor),
         {:ok, drafts} <- apply_edits(drafts, edits, actor),
         {:ok, inbox} <- AssignInbox.run(contact.campaign_id, actor: actor),
         snapshot = build_snapshot(sequence),
         {:ok, contact} <- approve_contact(contact, inbox, snapshot, sequence.version, actor),
         {:ok, _} <- schedule_step_one(drafts, inbox, actor),
         {:ok, _} <- approve_other_steps(drafts, actor),
         {:ok, _} <- maybe_bump_streak(contact.campaign_id, drafts, actor) do
      {:ok, %{contact_id: contact.id, inbox_id: inbox.id}}
    end
  end

  defp load_contact(id, actor) do
    Ash.get(CampaignContact, id,
      load: [:thread],
      actor: actor,
      authorize?: actor != nil
    )
  end

  defp load_sequence(campaign_id, actor) do
    {:ok,
     Sequence.get_for_campaign!(campaign_id,
       load: [:sequence_steps],
       actor: actor,
       authorize?: actor != nil
     )}
  end

  defp load_drafts(%{thread: nil}, _actor), do: {:ok, []}

  defp load_drafts(%{thread: %{id: tid}}, actor) do
    {:ok,
     Email.list_for_thread!(tid, actor: actor, authorize?: actor != nil)
     |> Enum.filter(&(&1.direction == :outbound and &1.status == :drafted))
     |> Enum.sort_by(& &1.step_position)}
  end

  # edits = %{"subject" => "<single subject>",
  #           "bodies" => %{step_position => body_string}}
  defp apply_edits(drafts, edits, actor) do
    subject = Map.get(edits, "subject")
    bodies = Map.get(edits, "bodies", %{})

    updated =
      Enum.map(drafts, fn email ->
        body = Map.get(bodies, email.step_position) || Map.get(bodies, "#{email.step_position}")
        new_subject = if subject in [nil, ""], do: email.user_subject, else: subject
        new_body = if body in [nil, ""], do: email.user_body, else: body

        if subject_changed?(email, new_subject) or body_changed?(email, new_body) do
          {:ok, e} =
            Email.update_user_fields(email, new_subject, new_body,
              actor: actor,
              authorize?: actor != nil
            )

          e
        else
          email
        end
      end)

    {:ok, updated}
  end

  defp subject_changed?(%{user_subject: s}, new), do: s != new
  defp body_changed?(%{user_body: b}, new), do: b != new

  defp build_snapshot(sequence) do
    %{
      "version" => sequence.version,
      "language" => sequence.language,
      "steps" =>
        Enum.map(sequence.sequence_steps, fn s ->
          %{
            "position" => s.position,
            "kind" => Atom.to_string(s.kind),
            "delay_days" => s.delay_days,
            "terminal_action" => s.terminal_action && Atom.to_string(s.terminal_action)
          }
        end)
    }
  end

  defp approve_contact(contact, inbox, snapshot, version, actor) do
    CampaignContact.approve(contact, inbox.id, snapshot, version,
      actor: actor,
      authorize?: actor != nil
    )
  end

  defp schedule_step_one([], _inbox, _actor), do: {:ok, nil}

  defp schedule_step_one(drafts, inbox, actor) do
    case Enum.find(drafts, &(&1.step_position == 0)) do
      nil ->
        {:ok, nil}

      step1 ->
        slot = naive_next_slot()

        {:ok, _} =
          Email.schedule(step1, slot, inbox.id,
            actor: actor,
            authorize?: actor != nil
          )

        {:ok, slot}
    end
  end

  defp approve_other_steps(drafts, actor) do
    drafts
    |> Enum.reject(&(&1.step_position == 0))
    |> Enum.each(fn e ->
      Email.mark_approved(e, actor: actor, authorize?: actor != nil)
    end)

    {:ok, :ok}
  end

  defp maybe_bump_streak(campaign_id, drafts, actor) do
    if clean?(drafts) do
      with {:ok, campaign} <-
             Campaign.get(campaign_id, actor: actor, authorize?: actor != nil),
           {:ok, _} <- Campaign.bump_auto_approve_streak(campaign, actor: actor) do
        {:ok, :bumped}
      end
    else
      {:ok, :skipped}
    end
  end

  defp clean?(drafts),
    do: Enum.all?(drafts, fn e -> is_nil(e.user_subject) and is_nil(e.user_body) end)

  # Naive scheduler — full §5.2 burst logic lands in E5. Snaps to Mon–Fri
  # 09:00–17:00 UTC, otherwise next workday 09:00.
  defp naive_next_slot do
    now = DateTime.utc_now()
    snap_into_workday(now)
  end

  defp snap_into_workday(dt) do
    cond do
      Date.day_of_week(DateTime.to_date(dt)) > 5 ->
        next_monday_9am(dt)

      dt.hour < 9 ->
        %{dt | hour: 9, minute: 0, second: 0, microsecond: {0, 0}}

      dt.hour >= 17 ->
        DateTime.add(dt, 1, :day) |> snap_into_workday()

      true ->
        dt
    end
  end

  defp next_monday_9am(dt) do
    add_days = 8 - Date.day_of_week(DateTime.to_date(dt))
    DateTime.add(dt, add_days, :day) |> Map.merge(%{hour: 9, minute: 0, second: 0, microsecond: {0, 0}})
  end
end
