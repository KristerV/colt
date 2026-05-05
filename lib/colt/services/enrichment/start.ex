defmodule Colt.Services.Enrichment.Start do
  @moduledoc """
  Confirm-time orchestrator. Samples up to 1000 companies for the campaign's
  filters, creates `CampaignCompany` join rows, locks the campaign at
  `:enriching` with `finalized_at`, and enqueues the first pipeline job
  (CheckWebsite) per row.
  """

  alias Colt.Filters
  alias Colt.Jobs.Enrichment.CheckWebsite
  alias Colt.Resources.{Campaign, CampaignCompany}

  def run(%Campaign{} = campaign, filters, actor) when is_map(filters) do
    with {:ok, companies} <- Filters.sample(filters),
         {:ok, ccs} <- bulk_create_ccs(campaign, companies),
         {:ok, _} <- enqueue_first_jobs(ccs),
         {:ok, campaign} <- finalize_campaign(campaign, filters, actor) do
      {:ok, %{count: length(ccs), campaign: campaign}}
    end
  end

  defp bulk_create_ccs(_campaign, []), do: {:ok, []}

  defp bulk_create_ccs(campaign, companies) do
    inputs = Enum.map(companies, &%{campaign_id: campaign.id, company_id: &1.id})

    case Ash.bulk_create(inputs, CampaignCompany, :create,
           return_records?: true,
           return_errors?: true,
           stop_on_error?: true
         ) do
      %Ash.BulkResult{status: :success, records: records} ->
        {:ok, records}

      %Ash.BulkResult{errors: errors} ->
        {:error, errors}
    end
  end

  defp enqueue_first_jobs(ccs) do
    Enum.each(ccs, fn cc ->
      %{campaign_company_id: cc.id} |> CheckWebsite.new() |> Oban.insert!()
    end)

    {:ok, length(ccs)}
  end

  defp finalize_campaign(campaign, filters, actor) do
    Campaign.finalize(campaign, filters, actor: actor)
  end
end
