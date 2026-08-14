defmodule Colt.Services.Sales.ReactivateOnReply do
  @moduledoc """
  A prospect who replies has just made themselves today's work, so a scheduled
  next action is stale the moment their reply lands: you parked them until
  Tuesday, they answered on Monday. Clearing `next_action_at` pops them out of
  **Later** and back into **Now**, untriaged — the same state auto-entry uses.

  Deliberately narrow:

    * only for contacts in the sales funnel — this is a sales-funnel move, and
      a contact who isn't in it has no bucket to return to;
    * only while open — a Won/Lost contact's bucket comes from `outcome`, and
      reopening a closed deal is a human's call;
    * only when a date is actually set — a contact already in Now needs no
      change, and writing one would put a no-op entry in their feed.

  Out-of-office auto-replies never reach here: `CategorizeReply` treats `:ooo`
  as "not a real reply" and defers the sequence instead.
  """

  alias Colt.Resources.CampaignContact
  alias Colt.Services.Sales.SetNextAction

  @reason "prospect replied"

  @doc """
  Clear `next_action_at` on `contact_id` when the guards above allow it.
  Returns `{:ok, contact}` when cleared, `{:ok, :skipped}` otherwise.
  """
  def run(contact_id, opts \\ []) when is_binary(contact_id) do
    actor = Keyword.get(opts, :actor)

    with {:ok, contact} <-
           Ash.get(CampaignContact, contact_id, actor: actor, authorize?: actor != nil) do
      if reactivate?(contact) do
        SetNextAction.run(contact.id, nil, Keyword.put_new(opts, :reason, @reason))
      else
        {:ok, :skipped}
      end
    end
  end

  defp reactivate?(%CampaignContact{} = contact) do
    contact.in_funnel_sales? and is_nil(contact.outcome) and not is_nil(contact.next_action_at)
  end
end
