defmodule Colt.Jobs.Ingest.Lt do
  @moduledoc """
  Monthly Oban worker for the full Lithuania ingest, in dependency order:

    1. **Registrų centras** (`Lt.Rc`) — basic registry + annual financial statements
       (companies, revenue). Creates/updates the company rows.
    2. **Sodra** (`Lt.Sodra`) — per-company headcount + EVRK/NACE via the stealth
       browser (`Colt.Services.Browser`), attached to the companies RC just wrote.

  Sodra runs second because it matches its rows to companies by `registry_code`, and
  is **non-fatal**: if it fails (e.g. Cloudflare tightens against the browser), RC's
  work is already persisted and the job still succeeds — the failure is logged for
  alerting, not propagated.

  ## Manual scheduling

      Colt.Jobs.Ingest.Lt.schedule()
      Colt.Jobs.Ingest.Lt.schedule(from: 3)   # resume RC from stage 3
  """

  require Logger

  use Oban.Worker,
    queue: :registry,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Colt.Services.Ingest.Lt.{Rc, Sodra}

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
    with {:ok, rc} <- Rc.run(from: Map.get(args, "from", 1)) do
      {:ok, %{rc: rc, sodra: run_sodra()}}
    end
  end

  # Enrichment step — never sink the LT ingest if the Sodra harvest fails
  # (Cloudflare block, browser down, DB error mid-import, …).
  defp run_sodra do
    case Sodra.run() do
      {:ok, result} ->
        result

      {:error, reason} ->
        Logger.error("LT Sodra step failed (RC ingest kept): #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("LT Sodra step crashed (RC ingest kept): #{Exception.message(e)}")
      {:error, :sodra_crashed}
  end
end
