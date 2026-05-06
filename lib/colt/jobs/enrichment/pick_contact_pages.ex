defmodule Colt.Jobs.Enrichment.PickContactPages do
  @moduledoc """
  §6.7 — pick up to 3 nav-extracted paths most likely to host named contacts,
  via heuristic prefilter then GLM 4.7. Enqueues `ScrapeContactPage` per path.

  When no paths qualify (no nav, all stripped) we still enqueue
  `ExtractContacts` against the landing page so we don't lose the run.
  """
  use Oban.Worker, queue: :ai, max_attempts: 2

  alias Colt.Jobs.Enrichment.{ExtractContacts, ScrapeContactPage}
  alias Colt.Resources.{CampaignCompany, Company, Page}
  alias Colt.Services.Enrichment.{PickContactPaths, Transition}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id}}) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, company} <- Company.get(cc.company_id) do
      Transition.stage(cc, :contact, :work)

      nav_pages = nav_pages_for(company)

      links =
        Enum.map(nav_pages, fn p ->
          %{path: p.path, title: p.title}
        end)

      case PickContactPaths.run(links, campaign_id: cc.campaign_id) do
        {:ok, []} ->
          # No contact-bearing pages — fall back to extracting from landing.
          %{campaign_company_id: cc.id} |> ExtractContacts.new() |> Oban.insert!()
          :ok

        {:ok, paths} ->
          Enum.each(paths, fn path ->
            %{campaign_company_id: cc.id, path: path}
            |> ScrapeContactPage.new()
            |> Oban.insert!()
          end)

          :ok

        {:error, reason} ->
          Transition.stage(cc, :contact, :fail)
          {:ok, _} = Transition.terminate(cc, :failed, stage: :contact, reason: short(reason))
          {:error, inspect(reason)}
      end
    end
  end

  defp short(reason) when is_binary(reason), do: String.slice(reason, 0, 240)
  defp short(reason), do: reason |> inspect() |> String.slice(0, 240)

  defp nav_pages_for(company) do
    case Page.for_company(company.id) do
      {:ok, pages} -> Enum.filter(pages, & &1.in_navigation)
      _ -> []
    end
  end
end
