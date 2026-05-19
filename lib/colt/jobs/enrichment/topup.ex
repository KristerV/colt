defmodule Colt.Jobs.Enrichment.Topup do
  @moduledoc """
  Throttled Oban heartbeat that drives `Enrichment.Topup.run/1`.

  Throttle via Oban uniqueness on `campaign_id` across `:available` and
  `:scheduled` states — while a topup is executing, completions can queue
  the *next* one; between executions there's at most one pending job.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      keys: [:campaign_id],
      states: [:available, :scheduled],
      period: :infinity
    ]

  alias Colt.Services.Enrichment.Topup

  @schedule_in 10

  def schedule(campaign_id, opts \\ []) when is_binary(campaign_id) do
    schedule_in = Keyword.get(opts, :schedule_in, @schedule_in)

    %{campaign_id: campaign_id}
    |> __MODULE__.new(schedule_in: schedule_in)
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"campaign_id" => campaign_id}}) do
    case Topup.run(campaign_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
