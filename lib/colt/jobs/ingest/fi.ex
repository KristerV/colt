defmodule Colt.Jobs.Ingest.Fi do
  @moduledoc """
  Monthly Oban worker that runs the PRH (Finland) ingest.

  Cron is wired in `config/config.exs` to fire on the 1st of each month
  on the `:registry` queue (concurrency 1, shared with other country
  ingests).
  """

  use Oban.Worker,
    queue: :registry,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Colt.Services.Ingest.Fi.Prh

  @impl true
  def timeout(_job), do: :infinity

  @impl true
  def perform(_job) do
    Prh.run()
  end
end
