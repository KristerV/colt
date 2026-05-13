defmodule Colt.Filters do
  @moduledoc """
  View 3 read paths. Builds the filter args, fans them into:

    * a count query
    * a 100-row random preview
    * a confirm-time random sample (capped by `:enrichment_max_companies`)
    * the per-bucket totals shown next to trajectory checkboxes
    * the top industries / regions used to populate the chip lists

  Service convention: `run/1` returns `{:ok, summary}` for the live view.
  Confirm-time sampling has its own entry point.
  """

  alias Colt.Resources.{AnnualReport, Company}

  @preview_limit 100
  @sample_limit Application.compile_env!(:colt, :enrichment_max_companies)
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
         {:ok, industries} <- top_industries(market) do
      {:ok,
       %{
         count: count,
         total: total_for_market(market),
         preview: preview,
         bucket_totals: buckets,
         top_industries: industries,
         last_sync: last_sync_at()
       }}
    end
  end

  @doc """
  Returns random `Company` records for the confirmed filter set, capped by
  `:enrichment_max_companies`.
  """
  def sample(filters) when is_map(filters) do
    Company.filtered(filters, query: [limit: @sample_limit])
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
