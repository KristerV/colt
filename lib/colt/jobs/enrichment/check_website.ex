defmodule Colt.Jobs.Enrichment.CheckWebsite do
  @moduledoc """
  §6.1 — registry-side website liveness check.

  Alive  → enqueue `FetchLanding`.
  Dead   → enqueue `GoogleSearch`.
  Skip   → company already enriched within the freshness window (spec §7);
           fast-forward to FetchLanding (which will itself short-circuit on
           a fresh page).
  """
  use Oban.Worker, queue: :scrape, max_attempts: 3

  alias Colt.Jobs.Enrichment.{FetchLanding, GoogleSearch}
  alias Colt.Resources.{CampaignCompany, Company}
  alias Colt.Services.Enrichment.{CheckAlive, Freshness, Transition}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id}}) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, company} <- Company.get(cc.company_id) do
      cond do
        Freshness.company_fresh?(company) and is_binary(company.website_url) ->
          enqueue(FetchLanding, cc)
          :ok

        is_binary(company.website_url) and company.website_url != "" ->
          run_check(cc, company)

        # We already searched recently and came up empty. Don't burn another
        # CSE call — short-circuit to :no_website for this campaign.
        Freshness.website_search_fresh?(company) ->
          Transition.stage(cc, :website, :fall)
          {:ok, _} = Transition.terminate(cc, :no_website, reason: "no website found (cached)")
          :ok

        true ->
          enqueue(GoogleSearch, cc)
          :ok
      end
    end
  end

  defp run_check(cc, company) do
    case CheckAlive.run(company.website_url) do
      {:ok, :alive} ->
        enqueue(FetchLanding, cc)
        :ok

      {:ok, :dead} ->
        enqueue(GoogleSearch, cc)
        :ok
    end
  end

  defp enqueue(worker, cc) do
    %{campaign_company_id: cc.id} |> worker.new() |> Oban.insert!()
  end
end
