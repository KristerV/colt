defmodule Colt.Jobs.Ingest.Lv do
  @moduledoc """
  Monthly Oban worker that runs the Latvia UR (Uzņēmumu reģistrs) ingest.

  See `docs/countries/lv.md`. Cron is wired in `config/config.exs` to fire
  on the 1st of every month on the `:registry` queue (concurrency 1),
  staggered with other country ingests so they never overlap.

  ## Manual scheduling

      # full ingest (all 5 stages)
      Colt.Jobs.Ingest.Lv.schedule()

      # resume from stage 3 (annual reports, NACE, growth)
      Colt.Jobs.Ingest.Lv.schedule(from: 3)

      # NACE only — note stage 1 must have run recently enough that
      # `vid_taxes_3y.csv` is still in the cache dir (a successful full
      # ingest wipes it).
      Colt.Jobs.Ingest.Lv.schedule(from: 4)
  """

  use Oban.Worker,
    queue: :registry,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Colt.Services.Ingest.Lv.Ur

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
    Ur.run(from: Map.get(args, "from", 1))
  end
end
