defmodule Colt.Services.Enrichment.Stats do
  @moduledoc """
  Snapshot of pipeline progress for the funnel meta strip:

      %{workers: 3, rate: 1.4, queue: 122, elapsed_s: 1287, eta_s: 532}

  Counts come from `oban_jobs`. Rate = jobs completed in the last 60s by any
  enrichment worker. Cheap enough to run every few seconds.
  """

  import Ecto.Query

  alias Colt.Repo

  @worker_prefix "Colt.Jobs.Enrichment."

  def run(finalized_at) do
    %{
      workers: count_state(["executing"]),
      queue: count_state(["available", "scheduled", "retryable"]),
      rate: rate_per_sec(),
      elapsed_s: elapsed_seconds(finalized_at),
      eta_s: nil
    }
    |> compute_eta()
  end

  defp count_state(states) do
    from(j in Oban.Job,
      where: like(j.worker, ^"#{@worker_prefix}%"),
      where: j.state in ^states
    )
    |> Repo.aggregate(:count, :id)
  end

  defp rate_per_sec do
    cutoff = DateTime.utc_now() |> DateTime.add(-60, :second)

    completed =
      from(j in Oban.Job,
        where: like(j.worker, ^"#{@worker_prefix}%"),
        where: j.state == "completed",
        where: j.completed_at >= ^cutoff
      )
      |> Repo.aggregate(:count, :id)

    Float.round(completed / 60.0, 2)
  end

  defp elapsed_seconds(nil), do: 0

  defp elapsed_seconds(%DateTime{} = ts) do
    DateTime.diff(DateTime.utc_now(), ts, :second) |> max(0)
  end

  defp compute_eta(%{queue: q, rate: r} = m) when r > 0,
    do: %{m | eta_s: round(q / r)}

  defp compute_eta(m), do: m
end
