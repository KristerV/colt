defmodule Colt.Services.Sending.IngestEnriched do
  @moduledoc """
  Promote enriched CampaignCompanies into CampaignContacts.

  For every CampaignCompany in the given campaign with a non-null
  `picked_person_id`, insert a CampaignContact `:pending_approval` row
  and an empty Thread. Idempotent — already-promoted contacts are left
  alone via the `unique_per_campaign` identity upsert.
  """

  alias Colt.Resources.{CampaignCompany, CampaignContact, Thread}

  def run(campaign_id, opts \\ []) when is_binary(campaign_id) do
    actor = Keyword.get(opts, :actor)

    with {:ok, picks} <- load_picks(campaign_id, actor),
         {:ok, inserted} <- promote_all(campaign_id, picks, actor) do
      {:ok, %{candidates: length(picks), inserted: inserted}}
    end
  end

  defp load_picks(campaign_id, actor) do
    rows =
      campaign_id
      |> CampaignCompany.list_for_campaign!(actor: actor, authorize?: actor != nil)
      |> Enum.filter(&(&1.picked_person_id != nil))

    {:ok, rows}
  end

  defp promote_all(campaign_id, picks, actor) do
    inserted =
      Enum.reduce(picks, 0, fn cc, acc ->
        case promote_one(campaign_id, cc.picked_person_id, actor) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)

    {:ok, inserted}
  end

  defp promote_one(campaign_id, person_id, actor) do
    with {:ok, contact} <-
           CampaignContact.promote(campaign_id, person_id,
             actor: actor,
             authorize?: actor != nil
           ),
         {:ok, _thread} <-
           Thread.create_for_contact(contact.id,
             actor: actor,
             authorize?: actor != nil
           ) do
      {:ok, contact}
    end
  end
end
