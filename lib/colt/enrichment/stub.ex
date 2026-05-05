defmodule Colt.Enrichment.Stub do
  @moduledoc """
  Phase 3 throwaway. Sleeps 2s and marks a `CampaignCompany` `:enriched`.
  Phase 4 replaces this with the real 9-job pipeline.
  """
  use Oban.Worker, queue: :enrichment, max_attempts: 1

  alias Colt.Resources.CampaignCompany

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id}}) do
    Process.sleep(2_000)

    case CampaignCompany.get(id) do
      {:ok, cc} ->
        cc |> CampaignCompany.mark_enriched() |> result()

      {:error, _} = err ->
        err
    end
  end

  defp result({:ok, _}), do: :ok
  defp result({:error, _} = err), do: err
end
