defmodule Colt.Services.Sales.MoveToStage do
  @moduledoc """
  Move a contact to a sales stage and record the move in the unified feed
  (from-stage → to-stage, actor-attributed, with an optional reason — e.g.
  the lost reason). One manual step in the sales CRM.
  """

  alias Colt.Resources.{CampaignContact, SalesStage}
  alias Colt.Services.Sales.RecordStatusEvent

  def run(contact_id, sales_stage_id, reason \\ nil, opts \\ [])
      when is_binary(contact_id) and is_binary(sales_stage_id) do
    actor = Keyword.get(opts, :actor)
    auth? = actor != nil

    with {:ok, contact} <-
           Ash.get(CampaignContact, contact_id,
             load: [:sales_stage],
             actor: actor,
             authorize?: auth?
           ),
         from = stage_name(contact.sales_stage),
         {:ok, stage} <- Ash.get(SalesStage, sales_stage_id, actor: actor, authorize?: auth?),
         {:ok, updated} <-
           CampaignContact.move_to_stage(contact, sales_stage_id, actor: actor, authorize?: auth?) do
      RecordStatusEvent.for_contact(contact.id, :sales_stage, from, stage.name,
        actor: actor,
        reason: normalize_reason(reason)
      )

      {:ok, updated}
    end
  end

  defp stage_name(%SalesStage{name: name}), do: name
  defp stage_name(_), do: nil

  defp normalize_reason(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_reason(_), do: nil
end
