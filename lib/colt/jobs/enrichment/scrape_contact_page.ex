defmodule Colt.Jobs.Enrichment.ScrapeContactPage do
  @moduledoc """
  §6.8 — fetch and convert a chosen contact page. Same logic as FetchLanding
  without the generic-email regex.

  When all selected contact pages for the company have been scraped (or are
  fresh), enqueue `ExtractContacts`.
  """
  use Oban.Worker, queue: :scrape, max_attempts: 3

  alias Colt.Jobs.Enrichment.ExtractContacts
  alias Colt.Resources.{CampaignCompany, Company, Page}
  alias Colt.Services.Enrichment.{ExtractContentLinks, Freshness, PickContactPaths, Transition}
  alias Colt.Services.Markdown.FromHtml
  alias Colt.Services.Scrape.Fetch

  @max_hops 2

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id, "path" => path} = args}) do
    hop = Map.get(args, "hop", 0)

    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, company} <- Company.get(cc.company_id) do
      page = existing(company, path)

      cond do
        match?(%Page{}, page) and Freshness.page_fresh?(page) ->
          enqueue_extract(cc)
          :ok

        true ->
          do_fetch(cc, company, path, hop)
      end
    end
  end

  defp do_fetch(cc, company, path, hop) do
    Transition.stage(cc, :contact, :work)
    url = absolute(company.website_url, path)

    case Fetch.run(url) do
      {:ok, %{html: html, fetcher: fetcher}} ->
        {:ok, markdown} = FromHtml.run(html)

        {:ok, _} =
          Page.upsert(%{
            company_id: company.id,
            path: path,
            title: nil,
            in_navigation: true,
            markdown: markdown,
            fetched_at: DateTime.utc_now(),
            fetcher: fetcher
          })

        maybe_recurse(cc, company, html, hop)
        enqueue_extract(cc)
        :ok

      {:error, reason} ->
        # Don't terminate the CC — other pages may still bring contacts.
        enqueue_extract(cc)
        {:error, inspect(reason)}
    end
  end

  # Always enqueue ExtractContacts on completion. Oban dedupes via unique,
  # and ExtractContacts itself snoozes if any sibling ScrapeContactPage is
  # still pending — race-free, no "am I last?" check needed.
  defp enqueue_extract(cc) do
    %{campaign_company_id: cc.id}
    |> ExtractContacts.new(
      unique: [
        period: :infinity,
        keys: [:campaign_company_id],
        states: [:available, :scheduled, :executing, :retryable]
      ]
    )
    |> Oban.insert!()
  end

  # When a contact page is itself a hub (e.g. /kontorid → /kontorid/tallinn),
  # extract its content links, ask the AI which look contact-bearing, and
  # enqueue more `ScrapeContactPage` jobs one hop deeper. Bounded by
  # `@max_hops`, deduped against pages we've already fetched.
  defp maybe_recurse(_cc, _company, _html, hop) when hop >= @max_hops, do: :ok

  defp maybe_recurse(cc, company, html, hop) do
    next_hop = hop + 1

    case ExtractContentLinks.run(html, company.website_url) do
      {:ok, []} ->
        :ok

      {:ok, links} ->
        candidates = drop_existing(links, company)

        case PickContactPaths.run(candidates, campaign_id: cc.campaign_id) do
          {:ok, paths} when paths != [] ->
            Enum.each(paths, fn p ->
              %{campaign_company_id: cc.id, path: p, hop: next_hop}
              |> __MODULE__.new()
              |> Oban.insert!()
            end)

          _ ->
            :ok
        end
    end
  end

  # Treat a path as "already fetched" only if a Page exists *with markdown*.
  # Nav-extracted Page stubs (in_navigation: true, markdown: nil) are not
  # actual fetches — recursing onto them is the whole point.
  defp drop_existing(links, company) do
    fetched =
      case Page.for_company(company.id) do
        {:ok, pages} ->
          pages
          |> Enum.filter(&is_binary(&1.markdown))
          |> MapSet.new(& &1.path)

        _ ->
          MapSet.new()
      end

    Enum.reject(links, &MapSet.member?(fetched, &1.path))
  end

  defp existing(company, path) do
    case Page.for_company(company.id) do
      {:ok, pages} -> Enum.find(pages, &(&1.path == path))
      _ -> nil
    end
  end

  defp absolute(base, path) do
    base = String.trim_trailing(base || "", "/")
    path = if String.starts_with?(path, "/"), do: path, else: "/" <> path
    base <> path
  end
end
