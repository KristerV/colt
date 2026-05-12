defmodule Colt.Services.Enrichment.RepickContacts do
  @moduledoc """
  Manual repair: for a campaign, find enriched companies whose extracted
  persons all have `matches_target_title = false` and re-run PickBestContact
  against the existing scraped persons. Sets exactly one person to
  `matches_target_title: true`. No re-scraping.

  Run with:

      mix run -e 'Colt.Services.Enrichment.RepickContacts.run("<campaign_id>") |> IO.inspect()'
  """

  alias Colt.Resources.{Campaign, CampaignCompany, Person}
  alias Colt.Services.Enrichment.PickBestContact

  def run(campaign_id) when is_binary(campaign_id) do
    with {:ok, campaign} <- Campaign.get(campaign_id),
         {:ok, rows} <- load_rows(campaign_id),
         {:ok, stats} <- repick_all(rows, campaign) do
      {:ok, stats}
    end
  end

  defp load_rows(campaign_id) do
    case CampaignCompany.list_unpicked_enriched(campaign_id,
           load: [company: [:persons]]
         ) do
      rows when is_list(rows) -> {:ok, rows}
      other -> {:error, other}
    end
  end

  defp repick_all(rows, campaign) do
    scanned = length(rows)

    updated =
      Enum.reduce(rows, 0, fn cc, acc ->
        case repick_one(cc, campaign) do
          :ok -> acc + 1
          _ -> acc
        end
      end)

    {:ok, %{scanned: scanned, updated: updated}}
  end

  defp repick_one(cc, campaign) do
    persons = cc.company.persons

    case persons do
      [] ->
        :skipped

      _ ->
        titles = Enum.map(persons, & &1.title)

        idx =
          case PickBestContact.run(campaign.target_job_title, titles, campaign_id: campaign.id) do
            {:ok, i} when is_integer(i) -> i
            _ -> 0
          end

        apply_pick(persons, idx)
    end
  end

  defp apply_pick(persons, idx) do
    persons
    |> Enum.with_index()
    |> Enum.each(fn {p, i} ->
      Person.set_target_match(p, i == idx)
    end)

    :ok
  end
end
