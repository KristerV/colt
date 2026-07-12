defmodule Colt.Filters do
  @moduledoc """
  View 3 read paths. Builds the filter args, fans them into:

    * a count query
    * a top-up random sample (capped by `:topup_max_sample`)
    * the per-bucket totals shown next to trajectory checkboxes
    * the top industries used to populate the chip lists

  Multi-market: filters carry `markets: [atom]`; an empty list matches nothing,
  so a campaign with no market picked short-circuits to an empty summary.

  Service convention: `run/1` returns `{:ok, summary}` for the live view.
  Confirm-time sampling has its own entry point.
  """

  alias Colt.Resources.{AnnualReport, Company}

  @sample_limit Application.compile_env!(:colt, :topup_max_sample)
  @top_industries 12

  @growth_buckets [:declining, :stagnant, :slow, :growing_2x, :growing_10x]

  @doc """
  Initial mount payload — counter, bucket totals, top industries, last sync.
  Filters can be `%{}`; an empty `markets` list yields an empty summary.
  """
  def run(filters) when is_map(filters) do
    case fetch_markets(filters) do
      [] ->
        {:ok, empty_summary()}

      markets ->
        with {:ok, count} <- count_filtered(filters),
             {:ok, buckets} <- bucket_totals(markets),
             {:ok, industries} <- top_industries(markets) do
          {:ok,
           %{
             count: count,
             total: total_for_markets(markets),
             bucket_totals: buckets,
             top_industries: industries,
             last_sync: last_sync_at()
           }}
        end
    end
  end

  defp empty_summary,
    do: %{count: 0, total: 0, bucket_totals: %{}, top_industries: [], last_sync: last_sync_at()}

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

  defp bucket_totals(markets) do
    counts =
      Map.new(@growth_buckets, fn bucket ->
        {:ok, n} =
          Company
          |> Ash.Query.for_read(:filtered, %{markets: markets, growth_buckets: [bucket]})
          |> Ash.count()

        {bucket, n}
      end)

    {:ok, counts}
  end

  defp top_industries(markets) do
    import Ecto.Query

    rows =
      Colt.Repo.all(
        from c in Company,
          where: c.market in ^markets and c.status == :registered,
          where: not is_nil(c.industry_code),
          group_by: fragment("LEFT(?, 4)", c.industry_code),
          order_by: [desc: count(c.id)],
          limit: @top_industries,
          select: {fragment("LEFT(?, 4)", c.industry_code), count(c.id)}
      )

    {:ok, rows}
  end

  defp total_for_markets(markets) do
    {:ok, n} =
      Company
      |> Ash.Query.for_read(:filtered, %{markets: markets})
      |> Ash.count()

    n
  end

  defp last_sync_at do
    import Ecto.Query
    Colt.Repo.aggregate(from(r in AnnualReport, []), :max, :updated_at)
  end

  defp fetch_markets(%{markets: m}) when is_list(m), do: m
  defp fetch_markets(_), do: []
end
