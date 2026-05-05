defmodule Colt.Services.Enrichment.Transition do
  @moduledoc """
  Atomic CC status transition + matching stage broadcast.

  Workers should call this rather than poking the resource and pubsub
  separately so the funnel never sees a status change without a stage event
  (or vice-versa).
  """

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

  `terminal` is one of `:enriched | :rejected | :no_website | :failed`.
  """
  def terminate(%CampaignCompany{} = cc, terminal, opts \\ []) do
    reason = Keyword.get(opts, :reason)

    {:ok, cc} =
      case terminal do
        :enriched -> CampaignCompany.mark_enriched(cc)
        :no_website -> CampaignCompany.mark_no_website(cc)
        :rejected -> CampaignCompany.mark_rejected(cc, reason)
        :failed -> CampaignCompany.mark_failed(cc)
      end

    patch = %{status: terminal} |> maybe_put(:rejection_reason, reason)
    Broadcast.row(cc.campaign_id, cc.id, patch)
    {:ok, cc}
  end

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
