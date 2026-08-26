defmodule Colt.Services.Costs.ContactCostByMonth do
  @moduledoc """
  Gross average cost per enriched contact, by month: total `api_calls` spend
  in the month (every scan, search and LLM call — successful or not) divided
  by how many `campaign_companies` reached `:enriched` status that month
  (bucketed by `Colt.Resources.CampaignCompany.enriched_count_by_month/1`, same
  approximation the funnel-by-month rollups already use elsewhere).

  Deviates from the project's prefer-Ash-actions rule for the same reason as
  `Colt.Services.Costs.MonthlySummary`: group-by with a ratio across two
  resources doesn't fit as a single read action.
  """
  import Ecto.Query

  alias Colt.Repo
  alias Colt.Resources.CampaignCompany

  def run(months_back \\ 12) when is_integer(months_back) and months_back > 0 do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-months_back * 31 * 86_400, :second)

    cost_by_month =
      from(c in "api_calls",
        where: c.inserted_at >= ^cutoff,
        group_by: fragment("to_char(?, 'YYYY-MM')", c.inserted_at),
        select: {fragment("to_char(?, 'YYYY-MM')", c.inserted_at), coalesce(sum(c.cost_usd), 0)}
      )
      |> Repo.all()
      |> Map.new()

    {:ok, enriched_rows} = CampaignCompany.enriched_count_by_month(months_back)
    enriched_by_month = Map.new(enriched_rows, &{&1.month, &1.count})

    months =
      (Map.keys(cost_by_month) ++ Map.keys(enriched_by_month))
      |> Enum.uniq()
      |> Enum.sort()

    rows =
      Enum.map(months, fn month ->
        cost = Map.get(cost_by_month, month, Decimal.new(0))
        enriched = Map.get(enriched_by_month, month, 0)

        %{
          month: month,
          cost_usd: cost,
          enriched: enriched,
          avg_cost_usd: avg(cost, enriched)
        }
      end)

    {:ok, rows}
  end

  defp avg(_cost, 0), do: nil
  defp avg(cost, enriched), do: Decimal.div(cost, Decimal.new(enriched))
end
