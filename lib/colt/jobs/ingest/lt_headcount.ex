defmodule Colt.Jobs.Ingest.LtHeadcount do
  @moduledoc """
  Monthly Oban worker that runs the Sodra (Lithuania) headcount ingest.
  Sodra is the LT state social-insurance fund and publishes per-employer
  headcount monthly — separate dataset from the registry pipeline
  (`LtIngest`), which is why this is a sidecar job.

  See `docs/countries/lt.md` for the Cloudflare blocker on
  `atvira.sodra.lt` and the three production options.

  Until a real fetcher is wired (via `opts[:fetcher]` or
  `config :colt, Colt.Services.Ingest.Lt.Sodra, fetcher: ...`), this
  worker fails fast with `{:error, :sodra_blocked_by_cloudflare}`.

  ## Manual scheduling

      Colt.Jobs.Ingest.LtHeadcount.schedule()
      Colt.Jobs.Ingest.LtHeadcount.schedule(from: 2)
  """

  use Oban.Worker,
    queue: :registry,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Colt.Services.Ingest.Lt.Sodra

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
    Sodra.run(from: Map.get(args, "from", 1))
  end
end
