defmodule Colt.Services.Costs.MonthlySummary do
  @moduledoc """
  Aggregate `api_calls` rows into per-month, per-provider totals.

  Returns `{:ok, [%{month: "2026-05", provider: :openrouter, calls: 42, cost_usd: Decimal}]}`
  ordered most-recent month first, then provider asc.

  This deviates from the project's prefer-Ash-actions rule because group-by
  with multiple aggregates doesn't fit cleanly as a single read action; we
  go straight to Ecto for one focused query.
  """
  import Ecto.Query

  alias Colt.Repo

  def run(months_back \\ 12) when is_integer(months_back) and months_back > 0 do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-months_back * 31 * 86_400, :second)

    rows =
      from(c in "api_calls",
        where: c.inserted_at >= ^cutoff,
        group_by: [fragment("to_char(?, 'YYYY-MM')", c.inserted_at), c.provider],
        order_by: [
          desc: fragment("to_char(?, 'YYYY-MM')", c.inserted_at),
          asc: c.provider
        ],
        select: %{
          month: fragment("to_char(?, 'YYYY-MM')", c.inserted_at),
          provider: c.provider,
          calls: count(c.id),
          cost_usd: coalesce(sum(c.cost_usd), 0)
        }
      )
      |> Repo.all()
      |> Enum.map(fn row ->
        %{row | provider: provider_atom(row.provider)}
      end)

    {:ok, rows}
  end

  defp provider_atom(p) when is_atom(p), do: p
  defp provider_atom(p) when is_binary(p), do: String.to_existing_atom(p)
end
