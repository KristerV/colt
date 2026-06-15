defmodule Colt.Services.Sending.RejectContactPick do
  @moduledoc """
  User pulls one contact out of sending on the writing page because it's the
  wrong *person* (the company may be a fine ICP fit — we just picked badly,
  and there was no better candidate to choose from). We:

    1. Distil the user's reason into a generalised contact-selection rule and
       save it as an `IcpLearning` with `target: :contact` (so `PickBestContact`
       avoids similar people next time / on re-check).
    2. Mark this CampaignCompany `:no_contacts` — it had people but none worth
       reaching, so it drops out of sending rather than the ICP-miss bucket.
    3. Destroy the CampaignContact, which cascades its thread and drafted
       emails, removing it from the sending funnel for good.

  We do NOT re-run the contact picker now — the learning only applies going
  forward.
  """

  alias Colt.Resources.{CampaignCompany, CampaignContact, IcpLearning}
  alias Colt.Services.Enrichment.GenerateContactLearning

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
         {:ok, rule} <-
           GenerateContactLearning.run(
             contact.campaign.target_job_title,
             contact_title(contact),
             reason,
             campaign_id: contact.campaign_id,
             subject: {:campaign_company, cc.id}
           ),
         {:ok, _learning} <-
           IcpLearning.create(contact.campaign_id, rule, :exclude, cc.company_id, :contact),
         {:ok, cc} <-
           CampaignCompany.mark_no_contacts(cc, %{reason: reason}, authorize?: false),
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

  defp contact_title(%{person: %{title: title}}), do: title
  defp contact_title(_), do: nil

  defp destroy_contact(contact, actor, authorize?) do
    Ash.destroy(contact, actor: actor, authorize?: authorize?)
  end
end
