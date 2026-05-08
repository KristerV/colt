defmodule Mix.Tasks.Colt.Ingest.Fi do
  @moduledoc """
  Runs the PRH (Finnish Patent and Registration Office) ingest synchronously.

      mix colt.ingest.fi
      mix colt.ingest.fi --from 3   # skip download + companies, only XBRL

  Downloads (cached) the PRH companies dump, converts it to NDJSON,
  imports companies, walks the iXBRL Open Data API for the configured
  fiscal-year ends, and recomputes growth buckets.
  """
  @shortdoc "Run the PRH (Finland) ingest"

  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    {parsed, _, _} = OptionParser.parse(args, strict: [from: :integer])
    opts = Keyword.take(parsed, [:from])

    case Colt.Services.Ingest.Fi.Prh.run(opts) do
      {:ok, summary} ->
        Mix.shell().info("PRH ingest complete:")
        Mix.shell().info(inspect(summary, pretty: true))

      {:error, reason} ->
        Mix.raise("PRH ingest failed: #{inspect(reason)}")
    end
  end
end
