defmodule Colt.Jobs.Enrichment.ScrapeContactPage do
  @moduledoc """
  §6.8 — fetch and convert a chosen contact page. Same logic as FetchLanding
  without the generic-email regex. Per-domain advisory lock; snooze on
  contention.

  When all selected contact pages for the company have been scraped (or are
  fresh), enqueue `ExtractContacts`.
  """
  use Oban.Worker, queue: :scrape, max_attempts: 3

  alias Colt.Jobs.Enrichment.ExtractContacts
  alias Colt.Locks
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
          maybe_finish(cc, company)

        true ->
          do_fetch(cc, company, path, hop)
      end
    end
  end

  defp do_fetch(cc, company, path, hop) do
    Transition.stage(cc, :contact, :work)
    url = absolute(company.website_url, path)
    host = uri_host(company.website_url)

    case Locks.with_domain_lock(host, fn -> Fetch.run(url) end) do
      :locked ->
        {:snooze, 1}

      {:ok, {:ok, %{html: html, fetcher: fetcher}}} ->
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
        maybe_finish(cc, company)

      {:ok, {:error, reason}} ->
        # Don't terminate the CC — other pages may still bring contacts.
        maybe_finish(cc, company)
        {:error, inspect(reason)}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
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

  defp drop_existing(links, company) do
    fetched =
      case Page.for_company(company.id) do
        {:ok, pages} -> MapSet.new(pages, & &1.path)
        _ -> MapSet.new()
      end

    Enum.reject(links, &MapSet.member?(fetched, &1.path))
  end

  # Enqueue ExtractContacts once when no other ScrapeContactPage jobs are
  # still queued or running for this CC. Cheap query: count non-completed
  # ScrapeContactPage rows for this campaign_company_id.
  defp maybe_finish(cc, _company) do
    if last_pending?(cc.id) do
      Transition.stage(cc, :contact, :done)
      %{campaign_company_id: cc.id} |> ExtractContacts.new() |> Oban.insert!()
    end

    :ok
  end

  defp last_pending?(cc_id) do
    import Ecto.Query

    cc_id_str = to_string(cc_id)

    q =
      from j in Oban.Job,
        where: j.worker == "Colt.Jobs.Enrichment.ScrapeContactPage",
        where: j.state in ["available", "scheduled", "executing", "retryable"],
        where: fragment("?->>'campaign_company_id' = ?", j.args, ^cc_id_str)

    Colt.Repo.aggregate(q, :count, :id) <= 1
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

  defp uri_host(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: h} when is_binary(h) -> h
      _ -> ""
    end
  end

  defp uri_host(_), do: ""
end
