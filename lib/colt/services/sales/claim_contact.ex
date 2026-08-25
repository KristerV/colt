defmodule Colt.Services.Sales.ClaimContact do
  @moduledoc """
  Assign a sales-funnel contact to the acting user — "I'm dealing with
  this." Always overwrites whoever had it before; there's no contest to
  arbitrate, just who's on it now.
  """

  alias Colt.Resources.CampaignContact
  alias Colt.Services.Sales.RecordStatusEvent

  @doc """
  Claim `contact_id` for `opts[:actor]`. Returns `{:ok, contact}`.
  """
  def run(contact_id, opts \\ []) when is_binary(contact_id) do
    actor = Keyword.fetch!(opts, :actor)

    with {:ok, contact} <- Ash.get(CampaignContact, contact_id, actor: actor, load: :assigned_to),
         from = contact.assigned_to && contact.assigned_to.email,
         {:ok, updated} <- CampaignContact.claim(contact, actor: actor) do
      RecordStatusEvent.for_contact(contact.id, :assigned, from, actor.email, actor: actor)
      {:ok, updated}
    end
  end
end
