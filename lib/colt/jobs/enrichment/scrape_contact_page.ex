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
  alias Colt.Services.Enrichment.{Freshness, Transition}
  alias Colt.Services.Markdown.FromHtml
  alias Colt.Services.Scrape.Fetch

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id, "path" => path}}) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, company} <- Company.get(cc.company_id) do
      page = existing(company, path)

      cond do
        match?(%Page{}, page) and Freshness.page_fresh?(page) ->
          maybe_finish(cc, company)

        true ->
          do_fetch(cc, company, path)
      end
    end
  end

  defp do_fetch(cc, company, path) do
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

        maybe_finish(cc, company)

      {:ok, {:error, reason}} ->
        # Don't terminate the CC — other pages may still bring contacts.
        maybe_finish(cc, company)
        {:error, inspect(reason)}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
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
