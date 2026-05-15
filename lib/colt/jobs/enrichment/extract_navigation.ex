defmodule Colt.Jobs.Enrichment.ExtractNavigation do
  @moduledoc """
  §6.4 — pull nav/header/footer anchors from the landing HTML and upsert
  `Page{in_navigation: true, markdown: nil}` for each unique same-host path.

  Receives the raw HTML in args (FetchLanding hands it off so we don't
  re-scrape).

  No downstream enqueue from here — `PickContactPages` is enqueued by
  MatchICP on a successful match.
  """
  use Oban.Worker, queue: :scrape, max_attempts: 2, priority: 4

  alias Colt.Resources.{CampaignCompany, Company, Page}
  alias Colt.Services.Enrichment.ExtractNavLinks

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id} = args}) do
    html = Map.get(args, "html", "")

    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, company} <- Company.get(cc.company_id) do
      base = company.website_url || ""

      case ExtractNavLinks.run(html, base) do
        {:ok, []} ->
          :ok

        {:ok, links} ->
          Enum.each(links, fn %{path: path, title: title} ->
            if path != "/" do
              Page.upsert(%{
                company_id: company.id,
                path: path,
                title: title,
                in_navigation: true,
                markdown: nil,
                fetched_at: nil,
                fetcher: nil
              })
            end
          end)

          :ok
      end
    end
  end
end
