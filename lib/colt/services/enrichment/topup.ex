defmodule Colt.Services.Enrichment.Topup do
  @moduledoc """
  Rolling top-up that keeps a working window of companies in flight until
  the campaign hits its `target_contact_count` of enriched CCs (or the
  filtered pool is exhausted).

  Working-window rule:

      remaining = target - count(enriched)
      in_flight = count(pending or scraping)
      need      = max(remaining * 3, topup_min_batch) - in_flight

  Same formula at start and on every top-up. When `remaining <= 0` or the
  sample returns `[]`, the worker simply idles — the heartbeat is event-
  driven (every CC terminal transition schedules another Topup), so when
  the user later changes filters or target the next scheduled run picks
  the work back up.

  Concurrency: takes a row-level `SELECT … FOR UPDATE` on the campaign so
  two parallel runs can't double-sample.
  """

  import Ecto.Query

  alias Colt.Filters
  alias Colt.Jobs.Enrichment.CheckWebsite
  alias Colt.Repo
  alias Colt.Resources.{Campaign, CampaignCompany}
  alias Colt.Services.Enrichment.Broadcast

  @yield_multiplier 3
  @in_flight [:pending, :scraping]

  defp floor_batch, do: Application.fetch_env!(:colt, :topup_min_batch)

  def run(campaign_id) when is_binary(campaign_id) do
    Repo.transaction(fn ->
      with {:ok, campaign} <- lock_campaign(campaign_id),
           :enriching <- campaign.status,
           {enriched, in_flight} <- counts(campaign_id),
           {:ok, result} <- step(campaign, enriched, in_flight) do
        result
      else
        :draft -> :not_started
        :collecting -> :not_started
        :archived -> :archived
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp step(campaign, enriched, in_flight) do
    remaining = campaign.target_contact_count - enriched
    need = max(remaining * @yield_multiplier, floor_batch()) - in_flight

    cond do
      remaining <= 0 -> {:ok, :idle}
      need <= 0 -> {:ok, :idle}
      true -> sample_and_enqueue(campaign, need)
    end
  end

  defp sample_and_enqueue(campaign, need) do
    filters = atomize_filters(campaign.filters, campaign.market)

    case Filters.sample(filters, need, exclude_campaign_id: campaign.id) do
      {:ok, []} ->
        {:ok, :idle}

      {:ok, companies} ->
        with {:ok, ccs} <- bulk_create_ccs(campaign, companies),
             :ok <- enqueue_first_jobs(ccs) do
          Broadcast.rows_added(campaign.id, Enum.map(ccs, & &1.id))
          {:ok, %{enqueued: length(ccs)}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp lock_campaign(campaign_id) do
    case Repo.one(from c in Campaign, where: c.id == ^campaign_id, lock: "FOR UPDATE") do
      nil -> {:error, :not_found}
      campaign -> {:ok, campaign}
    end
  end

  defp counts(campaign_id) do
    enriched =
      Repo.one(
        from cc in CampaignCompany,
          where: cc.campaign_id == ^campaign_id and cc.status == :enriched,
          select: count(cc.id)
      ) || 0

    in_flight =
      Repo.one(
        from cc in CampaignCompany,
          where: cc.campaign_id == ^campaign_id and cc.status in ^@in_flight,
          select: count(cc.id)
      ) || 0

    {enriched, in_flight}
  end

  defp bulk_create_ccs(campaign, companies) do
    inputs = Enum.map(companies, &%{campaign_id: campaign.id, company_id: &1.id})

    case Ash.bulk_create(inputs, CampaignCompany, :create,
           return_records?: true,
           return_errors?: true,
           stop_on_error?: false
         ) do
      %Ash.BulkResult{status: status, records: records}
      when status in [:success, :partial_success] ->
        {:ok, records}

      %Ash.BulkResult{errors: errors} ->
        {:error, errors}
    end
  end

  defp enqueue_first_jobs(ccs) do
    Enum.each(ccs, fn cc ->
      %{campaign_company_id: cc.id} |> CheckWebsite.new() |> Oban.insert!()
    end)

    :ok
  end

  defp atomize_filters(filters, market) do
    %{
      market: market,
      industries: Map.get(filters, "industries", []),
      industries_exclude: Map.get(filters, "industries_exclude", []),
      growth_buckets:
        filters
        |> Map.get("growth_buckets", [])
        |> Enum.map(&maybe_atom/1),
      employees_min: Map.get(filters, "employees_min"),
      employees_max: Map.get(filters, "employees_max"),
      revenue_min: Map.get(filters, "revenue_min"),
      revenue_max: Map.get(filters, "revenue_max")
    }
  end

  defp maybe_atom(b) when is_binary(b), do: String.to_existing_atom(b)
  defp maybe_atom(a) when is_atom(a), do: a
end
