defmodule Colt.Jobs.Ingest.No do
  @moduledoc """
  Monthly Oban worker that runs the BRREG (Brønnøysundregistrene) ingest
  for the Norwegian market. See `docs/countries/no.md` and
  `Colt.Services.Ingest.No.Brreg`.

  Cron is wired in `config/config.exs` (`:registry` queue, concurrency 1).

  ## Manual scheduling

      Colt.Jobs.Ingest.No.schedule()
      Colt.Jobs.Ingest.No.schedule(from: 3)
  """

  use Oban.Worker,
    queue: :registry,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Colt.Services.Ingest.No.Brreg

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
    Brreg.run(from: Map.get(args, "from", 1))
  end
end
