defmodule Colt.Jobs.Enrichment.FetchLanding do
  @moduledoc """
  §6.3 — fetch the landing page (static, fall back to Wallaby), extract
  generic email, convert to markdown, persist `Page{path: "/"}`.

  Per-domain advisory lock around the fetch (spec §6 intro). On `:locked`,
  the job snoozes 1s.

  Hands off raw HTML to `ExtractNavigation` via job args (capped) and
  enqueues `SummarizeCompany`.
  """
  use Oban.Worker, queue: :scrape, max_attempts: 3

  alias Colt.Jobs.Enrichment.{ExtractNavigation, GoogleSearch, SummarizeCompany}
  alias Colt.Locks
  alias Colt.Resources.{CampaignCompany, Company, Page}
  alias Colt.Services.Enrichment.{ExtractGenericEmail, FailureMessage, Freshness, Transition}
  alias Colt.Services.Markdown.FromHtml
  alias Colt.Services.Scrape.Fetch

  @html_args_cap 400_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id}}) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, cc} <- Transition.begin(cc),
         {:ok, company} <- Company.get(cc.company_id) do
      Transition.stage(cc, :website, :work)

      cond do
        not is_binary(company.website_url) ->
          fallback_to_google(cc, company, "no website_url on company")

        true ->
          maybe_run(cc, company)
      end
    end
  end

  defp maybe_run(cc, company) do
    case existing_landing(company) do
      %Page{} = page ->
        if Freshness.page_fresh?(page) do
          # No stage broadcast — SummarizeCompany downstream marks :done.
          %{campaign_company_id: cc.id} |> SummarizeCompany.new() |> Oban.insert!()
          :ok
        else
          do_fetch(cc, company)
        end

      _ ->
        do_fetch(cc, company)
    end
  end

  defp do_fetch(cc, company) do
    Transition.stage(cc, :website, :work)
    host = uri_host(company.website_url)

    case Locks.with_domain_lock(host, fn -> Fetch.run(company.website_url) end) do
      :locked ->
        {:snooze, 1}

      {:ok, {:ok, %{html: html, fetcher: fetcher, final_url: final}}} ->
        finish_fetch(cc, company, html, fetcher, final)

      {:ok, {:error, reason}} ->
        fallback_to_google(cc, company, reason)

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  # Scrape failed (or URL missing). If we haven't already tried Google for
  # this company, retry via search. Otherwise terminate.
  defp fallback_to_google(cc, company, reason) do
    if company.website_source == :google do
      {user_msg, detail} = FailureMessage.run(:website, reason)
      Transition.stage(cc, :website, :fail)

      {:ok, _} =
        Transition.terminate(cc, :failed, stage: :website, reason: user_msg, detail: detail)

      :ok
    else
      %{campaign_company_id: cc.id} |> GoogleSearch.new() |> Oban.insert!()
      :ok
    end
  end

  defp finish_fetch(cc, company, html, fetcher, final_url) do
    {:ok, generic_email} = ExtractGenericEmail.run(html, uri_host(final_url))
    {:ok, markdown} = FromHtml.run(html)

    {:ok, _page} =
      Page.upsert(%{
        company_id: company.id,
        path: "/",
        title: nil,
        in_navigation: false,
        markdown: markdown,
        fetched_at: DateTime.utc_now(),
        fetcher: fetcher
      })

    if generic_email && generic_email != company.generic_email do
      {:ok, _} = Company.set_generic_email(company, generic_email)
    end

    enqueue_next(cc, html)
    :ok
  end

  defp enqueue_next(cc, html) do
    %{campaign_company_id: cc.id, html: cap_html(html)}
    |> ExtractNavigation.new()
    |> Oban.insert!()

    %{campaign_company_id: cc.id} |> SummarizeCompany.new() |> Oban.insert!()
  end

  defp cap_html(html) when is_binary(html), do: String.slice(html, 0, @html_args_cap)
  defp cap_html(_), do: ""

  defp existing_landing(company) do
    case Page.for_company(company.id) do
      {:ok, pages} -> Enum.find(pages, &(&1.path == "/"))
      _ -> nil
    end
  end

  defp uri_host(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: h} when is_binary(h) -> h
      _ -> ""
    end
  end

  defp uri_host(_), do: ""
end
