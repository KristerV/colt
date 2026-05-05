defmodule Mix.Tasks.Colt.Ingest do
  @moduledoc """
  Runs the rik.ee Estonia ingest synchronously.

      mix colt.ingest

  Downloads (cached) the public dumps, imports companies, patches details,
  imports the last three fiscal years of annual reports, and recomputes the
  growth bucket on every affected company.
  """
  @shortdoc "Run the rik.ee Estonia ingest"

  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    {parsed, _, _} = OptionParser.parse(args, strict: [from: :integer])
    opts = Keyword.take(parsed, [:from])

    case Colt.Services.Ingest.Ee.Rik.run(opts) do
      {:ok, summary} ->
        Mix.shell().info("Ingest complete:")
        Mix.shell().info(inspect(summary, pretty: true))

      {:error, reason} ->
        Mix.raise("Ingest failed: #{inspect(reason)}")
    end
  end
end
