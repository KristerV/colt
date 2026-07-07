defmodule Colt.Services.Sales.EnterSalesFunnel do
  @moduledoc """
  Auto-entry into the sales funnel. When the sending machine marks a contact
  interested (or call-ready), it drops into the first active stage and a
  system `StatusEvent` records the entry. Idempotent — a contact already in
  the funnel is left exactly where a human put it.
  """

  alias Colt.Resources.{CampaignContact, SalesStage}
  alias Colt.Services.Sales.RecordStatusEvent

  @doc """
  Enter `contact_id` into `stage_id`. Returns `{:ok, :already_in}` when the
  contact is already in a stage (no event written), or `{:ok, contact}` on a
  fresh entry.
  """
  def run(contact_id, stage_id, opts \\ [])
      when is_binary(contact_id) and is_binary(stage_id) do
    actor = Keyword.get(opts, :actor)
    auth? = actor != nil

    with {:ok, contact} <-
           Ash.get(CampaignContact, contact_id, actor: actor, authorize?: auth?) do
      case contact.sales_stage_id do
        nil -> enter(contact, stage_id, actor, auth?)
        _already -> {:ok, :already_in}
      end
    end
  end

  defp enter(contact, stage_id, actor, auth?) do
    with {:ok, stage} <- Ash.get(SalesStage, stage_id, actor: actor, authorize?: auth?),
         {:ok, updated} <-
           CampaignContact.enter_sales_funnel(contact, stage_id, actor: actor, authorize?: auth?) do
      RecordStatusEvent.for_contact(contact.id, :entry, nil, stage.name,
        actor: actor,
        reason: "entered sales funnel"
      )

      {:ok, updated}
    end
  end
end
