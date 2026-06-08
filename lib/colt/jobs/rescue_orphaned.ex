defmodule Colt.Jobs.RescueOrphaned do
  @moduledoc """
  Re-queues jobs left stranded in the `executing` state when the node died
  mid-run (crash, OOM, or a deploy that killed the BEAM before Oban could shut
  its queues down gracefully).

  Runs once at application startup, after Oban is up: it lists the executing
  jobs, cancels them (so they leave `executing`), then retries them back to
  `available`. Cancelling first is required because `retry_all_jobs` ignores
  jobs that are still `executing`.
  """
  use GenServer

  require Logger
  import Ecto.Query

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, nil, {:continue, :rescue}}
  end

  @impl true
  def handle_continue(:rescue, state) do
    run()
    {:noreply, state}
  end

  def run do
    with {:ok, jobs} <- list_executing(),
         {:ok, cancelled} <- cancel(jobs),
         {:ok, retried} <- retry(jobs) do
      log(jobs, cancelled, retried)
      {:ok, retried}
    end
  end

  defp list_executing do
    {:ok, Colt.Repo.all(where(Oban.Job, [j], j.state == "executing"))}
  end

  defp cancel([]), do: {:ok, 0}
  defp cancel(jobs), do: Oban.cancel_all_jobs(by_ids(jobs))

  defp retry([]), do: {:ok, 0}
  defp retry(jobs), do: Oban.retry_all_jobs(by_ids(jobs))

  defp by_ids(jobs) do
    ids = Enum.map(jobs, & &1.id)
    where(Oban.Job, [j], j.id in ^ids)
  end

  defp log([], _cancelled, _retried), do: :ok

  defp log(jobs, cancelled, retried) do
    workers = jobs |> Enum.map(& &1.worker) |> Enum.frequencies()

    Logger.warning(
      "RescueOrphaned: re-queued #{retried} orphaned executing jobs " <>
        "(cancelled #{cancelled}) by worker: #{inspect(workers)}"
    )
  end
end
