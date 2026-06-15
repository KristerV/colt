defmodule Colt.Services.Sending.RejectContactIcp do
  @moduledoc """
  User pulls one contact out of sending on the writing page because its
  company isn't a good ICP fit. Mirrors the enrichment funnel's "Not a good
  fit" learning, then acts on this specific company/contact:

    1. Distil the user's reason into a generalised ICP exclusion rule and
       save it as an `IcpLearning` (so similar companies are filtered next
       re-check).
    2. Mark this CampaignCompany `:rejected` in the enrichment phase — it
       lands in the "ICP miss" bucket with the reason recorded.
    3. Destroy the CampaignContact, which cascades its thread and drafted
       emails, removing it from the sending funnel for good.
  """

  alias Colt.Resources.{CampaignCompany, CampaignContact, IcpLearning}
  alias Colt.Services.Enrichment.GenerateIcpLearning

  def run(contact_id, reason, opts \\ [])
      when is_binary(contact_id) and is_binary(reason) do
    actor = Keyword.get(opts, :actor)
    authorize? = actor != nil

    with {:ok, contact} <-
           Ash.get(CampaignContact, contact_id,
             load: [campaign: [], person: [:company]],
             actor: actor,
             authorize?: authorize?
           ),
         {:ok, cc} <- campaign_company(contact),
         summary <- cc.company.ai_summary || "",
         {:ok, rule} <-
           GenerateIcpLearning.run(
             contact.campaign.icp_description || "",
             summary,
             reason,
             :exclude,
             campaign_id: contact.campaign_id,
             subject: {:campaign_company, cc.id}
           ),
         {:ok, _learning} <-
           IcpLearning.create(contact.campaign_id, rule, :exclude, cc.company_id),
         {:ok, cc} <- CampaignCompany.mark_rejected(cc, reason, authorize?: false),
         :ok <- destroy_contact(contact, actor, authorize?) do
      {:ok, %{campaign_company: cc, learning: rule}}
    end
  end

  defp campaign_company(%{campaign_id: campaign_id, person: %{company_id: company_id}}) do
    Ash.get(CampaignCompany, %{campaign_id: campaign_id, company_id: company_id},
      load: [:company],
      authorize?: false
    )
  end

  defp campaign_company(_), do: {:error, :no_company}

  defp destroy_contact(contact, actor, authorize?) do
    Ash.destroy(contact, actor: actor, authorize?: authorize?)
  end
end
