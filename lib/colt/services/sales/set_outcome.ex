defmodule Colt.Services.Sales.SetOutcome do
  @moduledoc """
  Close a sales conversation as won or lost — or reopen it by passing `nil`.

  Closing clears `next_action_at`: a finished conversation has no next action,
  and leaving a stale date behind would make a reopened contact land in
  **Later** on a date nobody chose. Reopening therefore always returns the
  contact to **Now**, where it gets triaged afresh.
  """

  alias Colt.Resources.CampaignContact
  alias Colt.Services.Sales.RecordStatusEvent

  @outcomes [:won, :lost]

  @doc """
  Set `outcome` (`:won`, `:lost`, or `nil` to reopen) on `contact_id`.
  `opts` may carry `:reason` — used for the lost reason. Returns
  `{:ok, contact}`.
  """
  def run(contact_id, outcome, opts \\ [])
      when is_binary(contact_id) and (outcome in @outcomes or is_nil(outcome)) do
    actor = Keyword.get(opts, :actor)
    auth? = actor != nil
    reason = normalize_reason(Keyword.get(opts, :reason))

    with {:ok, contact} <- Ash.get(CampaignContact, contact_id, actor: actor, authorize?: auth?),
         {:ok, updated} <-
           CampaignContact.set_outcome(
             contact,
             %{
               outcome: outcome,
               outcome_reason: reason,
               outcome_at: stamp(outcome),
               next_action_at: nil
             },
             actor: actor,
             authorize?: auth?
           ) do
      RecordStatusEvent.for_contact(contact.id, :outcome, label(contact.outcome), label(outcome),
        actor: actor,
        reason: reason
      )

      {:ok, updated}
    end
  end

  defp stamp(nil), do: nil
  defp stamp(_outcome), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp label(nil), do: nil
  defp label(:won), do: "Won"
  defp label(:lost), do: "Lost"

  defp normalize_reason(nil), do: nil

  defp normalize_reason(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
