defmodule Colt.Jobs.RikIngest do
  @moduledoc """
  Weekly Oban worker that runs the rik.ee Estonia ingest.

  See spec §3.1 / phases §1. Cron is wired in `config/config.exs` to fire
  Sunday 03:00 UTC on the `:registry` queue (concurrency 1).

  ## Manual scheduling

      # full ingest (all 4 stages)
      Colt.Jobs.RikIngest.schedule()

      # resume from stage 4 (annual reports + growth) — useful when
      # earlier stages already finished and a later stage crashed.
      Colt.Jobs.RikIngest.schedule(from: 4)
  """

  use Oban.Worker,
    queue: :registry,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Colt.Services.Ingest.Ee.Rik

  def schedule(opts \\ []) do
    opts
    |> Map.new()
    |> new()
    |> Oban.insert()
  end

  @impl true
  def timeout(_job), do: :infinity

  @impl true
  def perform(%Oban.Job{args: args}) do
    Rik.run(from: Map.get(args, "from", 1))
  end
end
