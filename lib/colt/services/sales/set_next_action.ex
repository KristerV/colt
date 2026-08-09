defmodule Colt.Services.Sales.SetNextAction do
  @moduledoc """
  Schedule when to next touch a contact — the one manual input that drives the
  funnel board. A future date parks them in **Later**; today, a past date, or
  `nil` puts them back in **Now**.

  Clearing the date is a real choice, not an absence: it says "this needs
  triage again", which is why `nil` is accepted rather than rejected.
  """

  alias Colt.Resources.CampaignContact
  alias Colt.SalesClock
  alias Colt.Services.Sales.RecordStatusEvent

  @doc """
  Set (or clear, with `nil`) `next_action_at` on `contact_id`.
  Returns `{:ok, contact}`.
  """
  def run(contact_id, next_action_at, opts \\ []) when is_binary(contact_id) do
    actor = Keyword.get(opts, :actor)
    auth? = actor != nil

    with {:ok, contact} <- Ash.get(CampaignContact, contact_id, actor: actor, authorize?: auth?),
         from = label(contact.next_action_at),
         {:ok, updated} <-
           CampaignContact.set_next_action(contact, next_action_at,
             actor: actor,
             authorize?: auth?
           ) do
      RecordStatusEvent.for_contact(contact.id, :next_action, from, label(next_action_at),
        actor: actor
      )

      {:ok, updated}
    end
  end

  defp label(nil), do: nil
  defp label(%DateTime{} = at), do: at |> SalesClock.to_local_date() |> Date.to_iso8601()
end
