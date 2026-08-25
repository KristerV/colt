defmodule Colt.Services.Sales.AssignContact do
  @moduledoc """
  Assign a sales-funnel contact to a user — the acting admin claiming it for
  themselves, or handing it to a teammate from the assign picker.
  """

  alias Colt.Resources.CampaignContact
  alias Colt.Services.Sales.RecordStatusEvent

  @doc """
  Assign `contact_id` to `user_id` on behalf of `opts[:actor]`. Returns `{:ok, contact}`.
  """
  def run(contact_id, user_id, opts \\ []) when is_binary(contact_id) and is_binary(user_id) do
    actor = Keyword.fetch!(opts, :actor)

    with {:ok, contact} <- Ash.get(CampaignContact, contact_id, actor: actor, load: :assigned_to),
         from = contact.assigned_to && contact.assigned_to.email,
         {:ok, updated} <-
           CampaignContact.assign(contact, user_id, actor: actor, load: :assigned_to) do
      RecordStatusEvent.for_contact(contact.id, :assigned, from, updated.assigned_to.email,
        actor: actor
      )

      {:ok, updated}
    end
  end
end
