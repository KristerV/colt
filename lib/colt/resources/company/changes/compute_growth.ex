defmodule Colt.Resources.Company.Changes.ComputeGrowth do
  @moduledoc """
  Recomputes `revenue_latest`, `employees_latest`, and `revenue_growth_bucket`
  from the company's `:annual_reports`.

  Bucket thresholds per spec §3.1:
  - `:declining` — latest < prev
  - `:stagnant`  — |Δ| ≤ 5%
  - `:slow`      — 5% < Δ ≤ 100%
  - `:growing_2x` — 100% < Δ ≤ 900%
  - `:growing_10x` — Δ > 900%
  - `nil`        — fewer than 2 reports with revenue
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Colt.Resources.AnnualReport

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.before_action(changeset, &compute/1)
  end

  defp compute(changeset) do
    company = changeset.data
    reports = list_reports(company.id)

    {revenue_latest, employees_latest} = latest_values(reports)
    bucket = growth_bucket(reports)

    changeset
    |> Changeset.force_change_attribute(:revenue_latest, revenue_latest)
    |> Changeset.force_change_attribute(:employees_latest, employees_latest)
    |> Changeset.force_change_attribute(:revenue_growth_bucket, bucket)
  end

  defp list_reports(company_id) do
    AnnualReport
    |> Ash.Query.filter(company_id == ^company_id)
    |> Ash.Query.sort(year: :desc)
    |> Ash.read!()
  end

  defp latest_values([]), do: {nil, nil}
  defp latest_values([latest | _]), do: {latest.revenue_eur, latest.employees}

  defp growth_bucket(reports) do
    with_revenue = Enum.filter(reports, &(&1.revenue_eur != nil))

    case with_revenue do
      [latest, prev | _] ->
        bucket_for(to_float(latest.revenue_eur), to_float(prev.revenue_eur))

      _ ->
        nil
    end
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n / 1
  defp to_float(_), do: 0.0

  defp bucket_for(latest, prev) when prev <= 0 and latest > 0, do: :growing_10x
  defp bucket_for(_latest, prev) when prev <= 0, do: :stagnant
  defp bucket_for(latest, prev) when latest < prev, do: :declining

  defp bucket_for(latest, prev) do
    delta = (latest - prev) / prev

    cond do
      delta <= 0.05 -> :stagnant
      delta <= 1.0 -> :slow
      delta <= 9.0 -> :growing_2x
      true -> :growing_10x
    end
  end
end
