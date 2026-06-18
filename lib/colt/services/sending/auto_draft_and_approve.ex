defmodule Colt.Services.Sending.AutoDraftAndApprove do
  @moduledoc """
  Drives a CampaignContact straight to `:approved` + step-1 scheduled
  without ever entering the writing view. Enqueued when at least one
  sequence has "auto" enabled.

  Steps:
    1. Pick uniformly at random among auto-enabled, already-written sequences.
    2. Run EmailWriter for that sequence to create drafted emails.
    3. Assign sticky inbox.
    4. Snapshot the picked sequence.
    5. Approve the contact with `auto_approved?: true`, stamping the sequence.
    6. Schedule step 1 via the burst scheduler.
    7. Mark remaining drafts as `:approved`.
  """

  alias Colt.Resources.{CampaignContact, OutboundEmail, Sequence}
  alias Colt.Services.Sending.{AssignInbox, EmailWriter, NextSlot}

  def run(contact_id, opts \\ []) when is_binary(contact_id) do
    actor = Keyword.get(opts, :actor)

    with {:ok, contact} <- load_contact(contact_id, actor),
         {:ok, sequence} <- pick_template(contact.campaign_id, actor),
         {:ok, _} <- EmailWriter.run(contact_id, sequence_id: sequence.id, actor: actor),
         {:ok, contact} <- load_contact(contact_id, actor),
         {:ok, drafts} <- load_drafts(contact, actor),
         :ok <- ensure_drafts_present(drafts),
         {:ok, inbox} <- AssignInbox.run(contact.campaign_id, actor: actor),
         snapshot = build_snapshot(sequence),
         {:ok, contact} <- approve(contact, inbox, sequence, snapshot, actor),
         {:ok, _} <- schedule_step_one(drafts, inbox, actor),
         {:ok, _} <- approve_other_steps(drafts, actor) do
      {:ok, %{contact_id: contact.id, inbox_id: inbox.id}}
    end
  end

  # Fair A/B rotation: among active variants that have been written at least
  # once, pick the one sent to the fewest contacts (ties → oldest) so sample
  # sizes stay balanced. Unseeded variants are skipped — never send blanks.
  defp pick_template(campaign_id, actor) do
    active =
      Sequence.list_enabled_for_campaign!(campaign_id, actor: actor, authorize?: actor != nil)
      |> Enum.filter(&seeded?(&1, actor))

    case active do
      [] ->
        {:error, :no_enabled_template}

      pool ->
        counts = sent_counts(campaign_id, actor)
        picked = Enum.min_by(pool, &Map.get(counts, &1.id, 0))

        Sequence.get(picked.id,
          load: [:sequence_steps],
          actor: actor,
          authorize?: actor != nil
        )
    end
  end

  # Contacts already committed to each variant (sequence_id stamped at approval).
  defp sent_counts(campaign_id, actor) do
    case CampaignContact.list_for_campaign(campaign_id, actor: actor, authorize?: actor != nil) do
      {:ok, contacts} ->
        contacts
        |> Enum.reject(&is_nil(&1.sequence_id))
        |> Enum.frequencies_by(& &1.sequence_id)

      _ ->
        %{}
    end
  end

  defp seeded?(sequence, actor) do
    case OutboundEmail.list_user_edited_for_sequence(sequence.id, 1,
           actor: actor,
           authorize?: actor != nil
         ) do
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end

  defp load_contact(id, actor) do
    Ash.get(CampaignContact, id, load: [:thread], actor: actor, authorize?: actor != nil)
  end

  defp load_drafts(%{thread: nil}, _), do: {:ok, []}

  defp load_drafts(%{thread: %{id: tid}}, actor) do
    {:ok,
     OutboundEmail.list_for_thread!(tid, actor: actor, authorize?: actor != nil)
     |> Enum.filter(&(&1.status == :drafted))
     |> Enum.sort_by(& &1.step_position)}
  end

  defp ensure_drafts_present([]), do: {:error, :no_drafts_to_approve}
  defp ensure_drafts_present([_ | _]), do: :ok

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

  defp approve(contact, inbox, sequence, snapshot, actor) do
    Ash.update(
      contact,
      %{
        assigned_email_account_id: inbox.id,
        sequence_id: sequence.id,
        sequence_snapshot: snapshot,
        sequence_version: sequence.version,
        auto_approved?: true
      },
      action: :approve,
      actor: actor,
      authorize?: actor != nil
    )
  end

  defp schedule_step_one([], _, _), do: {:ok, nil}

  defp schedule_step_one(drafts, inbox, actor) do
    case Enum.find(drafts, &(&1.step_position == 0)) do
      nil ->
        {:ok, nil}

      step1 ->
        with {:ok, slot} <-
               NextSlot.run(inbox, DateTime.utc_now(), step_position: 0, actor: actor),
             {:ok, _} <-
               OutboundEmail.schedule(step1, slot, inbox.id,
                 actor: actor,
                 authorize?: actor != nil
               ) do
          {:ok, slot}
        end
    end
  end

  defp approve_other_steps(drafts, actor) do
    drafts
    |> Enum.reject(&(&1.step_position == 0))
    |> Enum.each(fn e ->
      OutboundEmail.mark_approved(e, actor: actor, authorize?: actor != nil)
    end)

    {:ok, :ok}
  end
end
