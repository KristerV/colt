defmodule Colt.Services.Enrichment.Transition do
  @moduledoc """
  Atomic CC status transition + matching stage broadcast.

  Workers should call this rather than poking the resource and pubsub
  separately so the funnel never sees a status change without a stage event
  (or vice-versa).
  """

  alias Colt.Jobs.Enrichment.Topup
  alias Colt.Resources.CampaignCompany
  alias Colt.Services.Enrichment.Broadcast

  @doc """
  Broadcast a per-stage state change. Idempotent — workers may emit
  `:done` repeatedly on rerun without changing CC status.
  """
  def stage(%CampaignCompany{} = cc, stage, state) do
    Broadcast.stage(cc.campaign_id, cc.id, stage, state)
    :ok
  end

  @doc """
  Move CC to a terminal status and broadcast the row patch.

  `terminal` is one of
    `:enriched | :rejected | :no_website | :no_contacts | :verify_failed | :failed`.

  Pass `stage:` (one of `:website | :icp | :contact | :verify`) when
  terminating with `:failed` so the funnel can paint the right pill red on
  reload. `reason:` is a string shown to the user.
  """
  def terminate(%CampaignCompany{} = cc, terminal, opts \\ []) do
    reason = Keyword.get(opts, :reason)
    detail = Keyword.get(opts, :detail)
    stage = Keyword.get(opts, :stage)

    {:ok, cc} =
      case terminal do
        :enriched ->
          CampaignCompany.mark_enriched(cc)

        :no_website ->
          CampaignCompany.mark_no_website(cc)

        :rejected ->
          CampaignCompany.mark_rejected(cc, reason)

        :no_contacts ->
          CampaignCompany.mark_no_contacts(cc, %{reason: reason})

        :verify_failed ->
          CampaignCompany.mark_verify_failed(cc, reason)

        :failed ->
          CampaignCompany.mark_failed(cc, %{
            failed_stage: stage,
            reason: reason,
            detail: detail
          })
      end

    patch =
      %{status: terminal}
      |> maybe_put(:rejection_reason, reason)
      |> maybe_put(:failure_detail, detail)
      |> maybe_put(:failed_stage, stage)

    Broadcast.row(cc.campaign_id, cc.id, patch)
    Topup.schedule(cc.campaign_id)
    {:ok, cc}
  end

  @doc """
  Restart-safe entry point for pipeline workers.

  When a CC carries a terminal `:failed` this is a re-run of a discarded job
  (the underlying problem — usually an AI outage — having since cleared). Drop
  it back to in-flight and clear the stale failure fields so the worker can
  proceed and downstream stages (e.g. VerifyEmail) don't short-circuit on the
  lingering `:failed`. No-op for any non-failed status, so healthy runs take
  no extra write.
  """
  def resume(%CampaignCompany{status: :failed} = cc) do
    {:ok, cc} = CampaignCompany.clear_failure(cc)

    Broadcast.row(cc.campaign_id, cc.id, %{
      status: :scraping,
      failed_stage: nil,
      failure_detail: nil,
      rejection_reason: nil
    })

    {:ok, cc}
  end

  def resume(%CampaignCompany{} = cc), do: {:ok, cc}

  @doc """
  Move CC into `:scraping` (in-flight). No-ops if already past pending.
  """
  def begin(%CampaignCompany{status: :pending} = cc) do
    {:ok, cc} = CampaignCompany.mark_scraping(cc)
    Broadcast.row(cc.campaign_id, cc.id, %{status: :scraping})
    {:ok, cc}
  end

  def begin(%CampaignCompany{} = cc), do: {:ok, cc}

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end
