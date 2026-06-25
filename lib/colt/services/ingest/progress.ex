defmodule Colt.Services.Ingest.Progress do
  @moduledoc """
  Lightweight progress ticker for streaming ingest pipelines. Wrap any stream
  with `tick/2` and a `[info]` log line is emitted every 5,000 elements.
  """

  require Logger

  @every 5_000

  def tick(stream, label) do
    stream
    |> Stream.with_index(1)
    |> Stream.map(fn {item, i} ->
      if rem(i, @every) == 0, do: Logger.info("    #{label}: #{thousands(i)}")
      item
    end)
  end

  def done(label, count) do
    Logger.info("    #{label}: #{thousands(count)} (done)")
  end

  defp thousands(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
