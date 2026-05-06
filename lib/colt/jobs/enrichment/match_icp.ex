defmodule Colt.Jobs.Enrichment.MatchICP do
  @moduledoc """
  §6.6 — Claude Sonnet 4.5 decides whether the company matches the
  campaign's ICP description. Per-campaign — no caching across campaigns.

  Match  → enqueue PickContactPages.
  Reject → terminal `:rejected` with reason.
  """
  use Oban.Worker, queue: :ai, max_attempts: 2

  alias Colt.Jobs.Enrichment.PickContactPages
  alias Colt.Resources.{Campaign, CampaignCompany, Company}
  alias Colt.Services.Enrichment.{ClassifyIcp, FailureMessage, Transition}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id}}) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, company} <- Company.get(cc.company_id),
         {:ok, campaign} <- Campaign.get(cc.campaign_id, authorize?: false) do
      Transition.stage(cc, :icp, :work)

      icp = campaign.icp_description || ""
      summary = company.ai_summary || ""

      cond do
        icp == "" or summary == "" ->
          # No ICP supplied or no summary — treat as soft pass so we don't
          # gate everything on ICP. Mark :done since the stage is complete
          # from the user's perspective.
          Transition.stage(cc, :icp, :done)
          enqueue_next(cc)
          :ok

        true ->
          case ClassifyIcp.run(icp, summary, campaign_id: cc.campaign_id) do
            {:ok, %{match: true}} ->
              Transition.stage(cc, :icp, :done)
              enqueue_next(cc)
              :ok

            {:ok, %{match: false, reason: reason}} ->
              Transition.stage(cc, :icp, :fall)
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
end
