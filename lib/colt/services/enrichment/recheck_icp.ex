defmodule Colt.Services.Enrichment.RecheckIcp do
  @moduledoc """
  Per-CampaignCompany ICP re-check. Cancels this CC's outstanding pipeline
  jobs, resets CC fields (status, rejection_reason, failed_stage, picked
  person) without touching the shared Company-level data (ai_summary, pages,
  persons), and re-enqueues MatchICP.

  Other campaigns sharing the same Company are unaffected.
  """

  import Ecto.Query

  alias Colt.Jobs.Enrichment.MatchICP
  alias Colt.Resources.CampaignCompany
  alias Colt.Services.Enrichment.{Broadcast, Transition}

  def run(cc_id) when is_binary(cc_id) do
    with {:ok, cc} <- CampaignCompany.get(cc_id, authorize?: false),
         {:ok, _} <- cancel_jobs(cc.id),
         {:ok, cc} <- CampaignCompany.reset_for_icp_recheck(cc, authorize?: false),
         :ok <- broadcast_reset(cc),
         {:ok, _} <- enqueue_match_icp(cc) do
      {:ok, cc}
    end
  end

  defp cancel_jobs(cc_id) do
    q =
      from(j in Oban.Job,
        where: like(j.worker, "Colt.Jobs.Enrichment.%"),
        where: fragment("?->>'campaign_company_id' = ?", j.args, ^to_string(cc_id)),
        where: j.state in ["available", "scheduled", "executing", "retryable"]
      )

    Oban.cancel_all_jobs(q)
  end

  defp broadcast_reset(cc) do
    Broadcast.row(cc.campaign_id, cc.id, %{
      status: :scraping,
      rejection_reason: nil,
      failure_detail: nil,
      failed_stage: nil
    })

    Transition.stage(cc, :icp, :work)
    :ok
  end

  defp enqueue_match_icp(cc) do
    %{campaign_company_id: cc.id} |> MatchICP.new() |> Oban.insert!()
    {:ok, cc.id}
  end
end
