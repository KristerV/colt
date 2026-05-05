defmodule Colt.Jobs.RikIngest do
  @moduledoc """
  Weekly Oban worker that runs the rik.ee Estonia ingest.

  See spec §3.1 / phases §1. Cron is wired in `config/config.exs` to fire
  Sunday 03:00 UTC on the `:registry` queue (concurrency 1).
  """

  use Oban.Worker, queue: :registry, max_attempts: 1

  alias Colt.Services.Ingest.Ee.Rik

  @impl true
  def perform(_job) do
    Rik.run()
  end
end
