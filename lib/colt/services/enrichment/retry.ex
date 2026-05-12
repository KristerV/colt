defmodule Colt.Services.Enrichment.Retry do
  @moduledoc """
  Admin-only retry for a single CampaignCompany. Cancels in-flight pipeline
  jobs, deletes scraped pages and extracted persons, clears all enrichment
  fields on the company and resets the campaign_company status to `:pending`,
  then re-enqueues the first pipeline job.
  """

  import Ecto.Query

  alias Colt.Jobs.Enrichment.CheckWebsite
  alias Colt.Resources.{CampaignCompany, Company, Page, Person}

  def run(cc_id) when is_binary(cc_id) do
    with {:ok, cc} <- CampaignCompany.get(cc_id, authorize?: false, load: [:company]),
         {:ok, _} <- cancel_jobs(cc.id),
         {:ok, _} <- delete_persons(cc.company_id),
         {:ok, _} <- delete_pages(cc.company_id),
         {:ok, _} <- Company.reset_enrichment(cc.company, authorize?: false),
         {:ok, cc} <- CampaignCompany.reset(cc, authorize?: false),
         {:ok, _} <- enqueue_first(cc) do
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

  defp delete_persons(company_id) do
    {:ok, persons} = Person.for_company(company_id, authorize?: false)
    Enum.each(persons, &Ash.destroy!(&1, authorize?: false))
    {:ok, length(persons)}
  end

  defp delete_pages(company_id) do
    {:ok, pages} = Page.for_company(company_id, authorize?: false)
    Enum.each(pages, &Ash.destroy!(&1, authorize?: false))
    {:ok, length(pages)}
  end

  defp enqueue_first(cc) do
    %{campaign_company_id: cc.id} |> CheckWebsite.new() |> Oban.insert!()
    {:ok, cc.id}
  end
end
