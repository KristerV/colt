defmodule Colt.Jobs.Ingest.Dk do
  @moduledoc """
  Monthly Oban worker that runs the Denmark CVR/Virk ingest.

  See `docs/countries/dk.md` for what this produces (limited-company
  identity from public XBRL filings + revenue/employee snapshots from
  the same files). Cron is wired in `config/config.exs` to fire monthly
  on the `:registry` queue (concurrency 1), staggered from other
  country ingests.

  ## Manual scheduling

      # full ingest (download stub → annual reports → growth rollup)
      Colt.Jobs.Ingest.Dk.schedule()

      # resume from stage 3 (growth recompute only)
      Colt.Jobs.Ingest.Dk.schedule(from: 3)

      # bounded slice for verification
      Colt.Jobs.Ingest.Dk.schedule(max_filings: 1000)
  """

  use Oban.Worker,
    queue: :registry,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Colt.Services.Ingest.Dk.Cvr

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
    opts =
      []
      |> maybe_kw(args, "from", :from, &to_integer/1)
      |> maybe_kw(args, "max_filings", :max_filings, &to_integer/1)
      |> maybe_kw(args, "max_years", :max_years, &to_integer/1)

    Cvr.run(opts)
  end

  defp maybe_kw(opts, args, key, kw_key, cast) do
    case Map.get(args, key) do
      nil -> opts
      val -> Keyword.put(opts, kw_key, cast.(val))
    end
  end

  defp to_integer(n) when is_integer(n), do: n
  defp to_integer(s) when is_binary(s), do: String.to_integer(s)
end
