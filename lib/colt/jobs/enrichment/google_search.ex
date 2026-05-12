defmodule Colt.Jobs.Enrichment.GoogleSearch do
  @moduledoc """
  §6.2 — find a company's website via Google CSE when registry has none or
  registry's URL was dead.

  Hit  → save `website_url`, source `:google`, enqueue FetchLanding.
  Miss → terminal `:no_website`.
  """
  use Oban.Worker, queue: :ai, max_attempts: 2

  alias Colt.Jobs.Enrichment.FetchLanding
  alias Colt.Resources.{CampaignCompany, Company}
  alias Colt.Services.Enrichment.{Broadcast, FailureMessage, PickBestResult, Transition}
  alias Colt.Services.Search.Google

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id}}) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, cc} <- Transition.begin(cc),
         {:ok, company} <- Company.get(cc.company_id) do
      Transition.stage(cc, :website, :work)
      # No quotes: exact-phrase matching can miss companies whose names appear
      # with punctuation/casing variants on the web (e.g. "osaühing Reta Puit").
      # No region either — it biases Google toward local business registries
      # (teatmik.ee, infoturg.ee, …) and buries the real company site.
      query = company.name

      case Google.run(query, num: 10, campaign_id: cc.campaign_id, task: "google_search") do
        {:ok, []} ->
          mark_no_website(cc)

        {:ok, results} ->
          pick(cc, company, results)

        {:error, reason} ->
          fail(cc, reason)
      end
    end
  end

  defp pick(cc, company, results) do
    case PickBestResult.run(company, results, campaign_id: cc.campaign_id) do
      {:ok, :none} ->
        mark_no_website(cc)

      {:ok, url} ->
        {:ok, _} = Company.set_website(company, url, :google)
        Broadcast.row(cc.campaign_id, cc.id, %{website_url: url})
        Transition.stage(cc, :website, :done)
        %{campaign_company_id: cc.id} |> FetchLanding.new() |> Oban.insert!()
        :ok

      {:error, reason} ->
        fail(cc, reason)
    end
  end

  defp mark_no_website(cc) do
    Transition.stage(cc, :website, :fall)
    {:ok, _} = Transition.terminate(cc, :no_website)
    :ok
  end

  defp fail(cc, reason) do
    {user_msg, detail} = FailureMessage.run(:website, reason)
    Transition.stage(cc, :website, :fail)

    {:ok, _} =
      Transition.terminate(cc, :failed, stage: :website, reason: user_msg, detail: detail)

    {:error, detail}
  end
end
