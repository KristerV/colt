defmodule Colt.Jobs.Ingest.Lt do
  @moduledoc """
  Weekly Oban worker that runs the Lithuania Registrų centras ingest
  (basic registry + annual financial statements).

  See `docs/countries/lt.md` for the dataset list and the rationale for
  keeping the registry and headcount (Sodra) pipelines as separate Oban
  jobs (`LtIngest` + `LtHeadcountIngest`).

  ## Manual scheduling

      Colt.Jobs.Ingest.Lt.schedule()
      Colt.Jobs.Ingest.Lt.schedule(from: 3)
  """

  use Oban.Worker,
    queue: :registry,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Colt.Services.Ingest.Lt.Rc

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
    Rc.run(from: Map.get(args, "from", 1))
  end
end
