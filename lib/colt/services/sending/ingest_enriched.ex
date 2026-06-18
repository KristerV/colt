defmodule Colt.Services.Sending.IngestEnriched do
  @moduledoc """
  Bulk-promote every enriched CampaignCompany into CampaignContacts.

  For each CampaignCompany in the campaign with a non-null `picked_person_id`,
  promote a CampaignContact `:pending_approval` row (+ empty Thread) via
  `PromoteOne.promote_person`. Idempotent — already-promoted contacts are
  left alone via the `unique_per_campaign` identity upsert.

  Dev/admin utility only. The normal flow is pull-based now: Write mints one
  contact when it has nothing pending, and the auto starter mints one per open
  send slot. This bulk path no longer triggers auto-approve.
  """

  alias Colt.Resources.CampaignCompany
  alias Colt.Services.Sending.PromoteOne

  def run(campaign_id, opts \\ []) when is_binary(campaign_id) do
    actor = Keyword.get(opts, :actor)

    with {:ok, picks} <- load_picks(campaign_id, actor),
         {:ok, inserted_contacts} <- promote_all(campaign_id, picks, opts) do
      {:ok, %{candidates: length(picks), inserted: length(inserted_contacts)}}
    end
  end

  defp load_picks(campaign_id, actor) do
    rows =
      campaign_id
      |> CampaignCompany.list_for_campaign!(actor: actor, authorize?: actor != nil)
      |> Enum.filter(&(&1.picked_person_id != nil))

    {:ok, rows}
  end

  defp promote_all(campaign_id, picks, opts) do
    inserted =
      Enum.reduce(picks, [], fn cc, acc ->
        case PromoteOne.promote_person(campaign_id, cc.picked_person_id, opts) do
          {:ok, contact} -> [contact | acc]
          {:error, _} -> acc
        end
      end)

    {:ok, Enum.reverse(inserted)}
  end
end
