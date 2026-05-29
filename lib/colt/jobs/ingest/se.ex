defmodule Colt.Jobs.Ingest.Se do
  @moduledoc """
  Monthly Oban worker that runs the Bolagsverket (Sweden) ingest.

  Cron is wired in `config/config.exs` to fire on the 1st of each month
  on the `:registry` queue (concurrency 1, staggered with other country
  ingests so they serialise rather than thrash the box).

  Requires `:client_id` and `:client_secret` under
  `config :colt, :bolagsverket`. When either is missing the orchestrator
  returns `{:error, :missing_api_key}` and Oban will record the failure
  without retrying (max_attempts: 1).
  """

  use Oban.Worker,
    queue: :registry,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Colt.Services.Ingest.Se.Bolagsverket

  @impl true
  def timeout(_job), do: :infinity

  @impl true
  def perform(_job) do
    Bolagsverket.run()
  end
end
