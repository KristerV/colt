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
  alias Colt.Services.Enrichment.{PickBestResult, Transition}
  alias Colt.Services.Search.Google

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id}}) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, company} <- Company.get(cc.company_id) do
      Transition.stage(cc, :website, :work)
      query = "\"#{company.name}\" #{company.region || ""}" |> String.trim()

      case Google.run(query, num: 5, campaign_id: cc.campaign_id) do
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
    Transition.stage(cc, :website, :fail)
    {:ok, _} = Transition.terminate(cc, :failed, stage: :website, reason: short(reason))
    {:error, inspect(reason)}
  end

  defp short(reason) when is_binary(reason), do: String.slice(reason, 0, 240)
  defp short(reason), do: reason |> inspect() |> String.slice(0, 240)
end
