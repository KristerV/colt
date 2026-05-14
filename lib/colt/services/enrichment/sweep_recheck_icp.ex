defmodule Colt.Services.Enrichment.SweepRecheckIcp do
  @moduledoc """
  Campaign-level ICP re-check. Iterates CampaignCompany rows in terminal
  states that have a usable summary, and calls RecheckIcp per row.

  Eligible statuses:
    * :enriched           — was a match, may now reject
    * :rejected           — was rejected at ICP, may now match
    * :failed (stage :icp) — LLM/API error on previous ICP call

  Skipped:
    * :no_website / :failed website — no summary to classify against
    * :no_contacts          — ICP already passed; user has decided this is "no point"
    * :pending / :scraping  — already in-flight; will see fresh learnings naturally
  """

  alias Colt.Resources.CampaignCompany
  alias Colt.Services.Enrichment.RecheckIcp

  def run(campaign_id) when is_binary(campaign_id) do
    with {:ok, ccs} <- CampaignCompany.list_for_campaign(campaign_id, authorize?: false),
         eligible <- Enum.filter(ccs, &eligible?/1),
         {:ok, n} <- queue_all(eligible) do
      {:ok, %{queued: n, total: length(ccs)}}
    end
  end

  defp eligible?(%{status: :enriched}), do: true
  defp eligible?(%{status: :rejected}), do: true
  defp eligible?(%{status: :failed, failed_stage: :icp}), do: true
  defp eligible?(_), do: false

  defp queue_all(ccs) do
    Enum.each(ccs, fn cc -> {:ok, _} = RecheckIcp.run(cc.id) end)
    {:ok, length(ccs)}
  end
end
