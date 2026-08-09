defmodule Colt.Services.Sales.EnterSalesFunnel do
  @moduledoc """
  Entry into the sales funnel. The contact lands with no next action, which
  puts them in the **Now** bucket — freshly entered means not yet triaged, and
  that is exactly the state that should be visible.

  Idempotent: a contact already in the funnel is left exactly as a human left
  them, and no duplicate entry event is written.
  """

  alias Colt.Resources.CampaignContact
  alias Colt.Services.Sales.RecordStatusEvent

  @doc """
  Enter `contact_id` into the sales funnel. Returns `{:ok, :already_in}` when
  the contact is already a member (no event written), or `{:ok, contact}` on a
  fresh entry.
  """
  def run(contact_id, opts \\ []) when is_binary(contact_id) do
    actor = Keyword.get(opts, :actor)
    auth? = actor != nil

    with {:ok, contact} <-
           Ash.get(CampaignContact, contact_id, actor: actor, authorize?: auth?) do
      case contact.in_funnel_sales? do
        false -> enter(contact, actor, auth?)
        true -> {:ok, :already_in}
      end
    end
  end

  defp enter(contact, actor, auth?) do
    with {:ok, updated} <-
           CampaignContact.enter_sales_funnel(contact, actor: actor, authorize?: auth?) do
      RecordStatusEvent.for_contact(contact.id, :entry, nil, "Now",
        actor: actor,
        reason: "entered sales funnel"
      )

      {:ok, updated}
    end
  end
end
