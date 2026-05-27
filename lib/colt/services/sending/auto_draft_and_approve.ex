defmodule Colt.Services.Sending.AutoDraftAndApprove do
  @moduledoc """
  Drives a CampaignContact straight to `:approved` + step-1 scheduled
  without ever entering the writing view. Used when
  `Campaign.auto_approve_on?` is true.

  Steps:
    1. Run EmailWriter to create drafted emails (ai_* only).
    2. Assign sticky inbox.
    3. Snapshot the campaign's sequence.
    4. Approve the contact with `auto_approved?: true`.
    5. Schedule step 1 via the burst scheduler.
    6. Mark remaining drafts as `:approved`.
  """

  alias Colt.Resources.{CampaignContact, OutboundEmail, Sequence}
  alias Colt.Services.Sending.{AssignInbox, EmailWriter, NextSlot}

  def run(contact_id, opts \\ []) when is_binary(contact_id) do
    actor = Keyword.get(opts, :actor)

    with {:ok, _} <- EmailWriter.run(contact_id, actor: actor),
         {:ok, contact} <- load_contact(contact_id, actor),
         {:ok, drafts} <- load_drafts(contact, actor),
         :ok <- ensure_drafts_present(drafts),
         {:ok, sequence} <- load_sequence(contact.campaign_id, actor),
         {:ok, inbox} <- AssignInbox.run(contact.campaign_id, actor: actor),
         snapshot = build_snapshot(sequence),
         {:ok, contact} <- approve(contact, inbox, snapshot, sequence.version, actor),
         {:ok, _} <- schedule_step_one(drafts, inbox, actor),
         {:ok, _} <- approve_other_steps(drafts, actor) do
      {:ok, %{contact_id: contact.id, inbox_id: inbox.id}}
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

  defp load_sequence(campaign_id, actor) do
    {:ok,
     Sequence.get_for_campaign!(campaign_id,
       load: [:sequence_steps],
       actor: actor,
       authorize?: actor != nil
     )}
  end

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

  defp approve(contact, inbox, snapshot, version, actor) do
    Ash.update(
      contact,
      %{
        assigned_email_account_id: inbox.id,
        sequence_snapshot: snapshot,
        sequence_version: version,
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
