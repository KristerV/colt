defmodule Colt.Filters do
  @moduledoc """
  View 3 read paths. Builds the filter args, fans them into:

    * a count query
    * a 100-row random preview
    * a top-up random sample (capped by `:topup_max_sample`)
    * the per-bucket totals shown next to trajectory checkboxes
    * the top industries / regions used to populate the chip lists

  Service convention: `run/1` returns `{:ok, summary}` for the live view.
  Confirm-time sampling has its own entry point.
  """

  alias Colt.Resources.{AnnualReport, Company}

  @preview_limit 100
  @sample_limit Application.compile_env!(:colt, :topup_max_sample)
  @top_industries 12

  @growth_buckets [:declining, :stagnant, :slow, :growing_2x, :growing_10x]

  @doc """
  Initial mount payload — counter, preview, bucket totals, top chips, last sync.
  Filters can be `%{}`; market is required.
  """
  def run(filters) when is_map(filters) do
    with {:ok, market} <- fetch_market(filters),
         {:ok, count} <- count_filtered(filters),
         {:ok, preview} <- preview_filtered(filters),
         {:ok, buckets} <- bucket_totals(market),
         {:ok, industries} <- top_industries(market),
         {:ok, categories} <- Company.top_categories(filters) do
      {:ok,
       %{
         count: count,
         total: total_for_market(market),
         preview: preview,
         bucket_totals: buckets,
         top_industries: industries,
         filtered_categories: categories,
         last_sync: last_sync_at()
       }}
    end
  end

  @doc """
  Returns random `Company` records for the confirmed filter set, capped by
  `:topup_max_sample`. Pass `exclude_campaign_id:` to skip companies already
  in that campaign (used by Topup to avoid re-picking).
  """
  def sample(filters, limit \\ @sample_limit, opts \\ [])
      when is_map(filters) and is_integer(limit) and is_list(opts) do
    args =
      case Keyword.get(opts, :exclude_campaign_id) do
        nil -> filters
        id -> Map.put(filters, :exclude_campaign_id, id)
      end

    Company.filtered(args, query: [limit: min(limit, @sample_limit)])
  end

  defp count_filtered(filters) do
    Company
    |> Ash.Query.for_read(:filtered, filters)
    |> Ash.count()
  end

  defp preview_filtered(filters) do
    Company.filtered(filters, query: [limit: @preview_limit])
  end

  defp bucket_totals(market) do
    counts =
      Map.new(@growth_buckets, fn bucket ->
        {:ok, n} =
          Company
          |> Ash.Query.for_read(:filtered, %{market: market, growth_buckets: [bucket]})
          |> Ash.count()

        {bucket, n}
      end)

    {:ok, counts}
  end

  defp top_industries(market) do
    import Ecto.Query

    rows =
      Colt.Repo.all(
        from c in Company,
          where: c.market == ^market and c.status == :registered,
          where: not is_nil(c.industry_code),
          group_by: fragment("LEFT(?, 4)", c.industry_code),
          order_by: [desc: count(c.id)],
          limit: @top_industries,
          select: {fragment("LEFT(?, 4)", c.industry_code), count(c.id)}
      )

    {:ok, rows}
  end

  defp total_for_market(market) do
    {:ok, n} =
      Company
      |> Ash.Query.for_read(:filtered, %{market: market})
      |> Ash.count()

    n
  end

  defp last_sync_at do
    import Ecto.Query
    Colt.Repo.aggregate(from(r in AnnualReport, []), :max, :updated_at)
  end

  defp fetch_market(%{market: m}) when not is_nil(m), do: {:ok, m}
  defp fetch_market(_), do: {:error, :market_required}
end
