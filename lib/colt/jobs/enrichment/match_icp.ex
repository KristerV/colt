defmodule Colt.Jobs.Enrichment.MatchICP do
  @moduledoc """
  §6.6 — Claude Sonnet 4.5 decides whether the company matches the
  campaign's ICP description, plus any user-added IcpLearning exclusions.

  Match  → enqueue PickContactPages.
  Reject → terminal `:rejected` with reason (also nils picked_person_id so
           a previously :enriched row drops out of the export cleanly).
  """
  use Oban.Worker,
    queue: :ai,
    max_attempts: 2,
    priority: 5,
    unique: [
      fields: [:worker, :args],
      keys: [:campaign_company_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Colt.Jobs.Enrichment.PickContactPages
  alias Colt.Resources.{Campaign, CampaignCompany, Company, IcpLearning}
  alias Colt.Services.Enrichment.{ClassifyIcp, FailureMessage, Transition}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id}}) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, cc} <- Transition.resume(cc),
         {:ok, company} <- Company.get(cc.company_id),
         {:ok, campaign} <- Campaign.get(cc.campaign_id, authorize?: false) do
      Transition.stage(cc, :icp, :work)

      icp = campaign.icp_description || ""
      summary = company.ai_summary || ""
      learnings = load_learnings(cc.campaign_id)

      cond do
        icp == "" or summary == "" ->
          Transition.stage(cc, :icp, :done)
          enqueue_next(cc)
          :ok

        true ->
          case ClassifyIcp.run(icp, summary,
                 campaign_id: cc.campaign_id,
                 subject: {:campaign_company, cc.id},
                 business_model: campaign.business_model,
                 learnings: learnings
               ) do
            {:ok, %{match: true, reason: reason}} ->
              {:ok, _} = CampaignCompany.set_icp_reason(cc, reason, authorize?: false)
              Transition.stage(cc, :icp, :done)
              enqueue_next(cc)
              :ok

            {:ok, %{match: false, reason: reason}} ->
              Transition.stage(cc, :icp, :fall)
              {:ok, _} = CampaignCompany.set_picked_person(cc, nil, authorize?: false)
              {:ok, _} = Transition.terminate(cc, :rejected, reason: reason)
              :ok

            {:error, reason} ->
              {user_msg, detail} = FailureMessage.run(:icp, reason)
              Transition.stage(cc, :icp, :fail)

              {:ok, _} =
                Transition.terminate(cc, :failed,
                  stage: :icp,
                  reason: user_msg,
                  detail: detail
                )

              {:error, detail}
          end
      end
    end
  end

  defp enqueue_next(cc) do
    %{campaign_company_id: cc.id} |> PickContactPages.new() |> Oban.insert!()
  end

  defp load_learnings(campaign_id) do
    case IcpLearning.list_by_target(campaign_id, :company, authorize?: false) do
      {:ok, learnings} -> Enum.map(learnings, &%{body: &1.body, kind: &1.kind})
      _ -> []
    end
  end
end
