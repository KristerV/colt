defmodule Colt.Services.Scrape.Fetch do
  @moduledoc """
  Top-level fetcher. Tries `Static` first, runs `DetectSpa` on the result, and
  falls back to `Wallaby` if needed. Adds a small jitter delay before the
  request as a politeness default.

  Returns
      {:ok, %{html, fetcher: :static | :wallaby, status, final_url}}
      | {:error, reason}
  """

  alias Colt.Services.Scrape.{DetectSpa, Static, Wallaby}

  @default_jitter_ms 250

  def run(url, opts \\ []) when is_binary(url) do
    jitter = Keyword.get(opts, :jitter_ms, @default_jitter_ms)
    if jitter > 0, do: Process.sleep(:rand.uniform(jitter))

    with {:ok, static} <- Static.run(url),
         {:ok, verdict} <- DetectSpa.run(static) do
      case verdict do
        :static ->
          {:ok, Map.put(static, :fetcher, :static)}

        :needs_wallaby ->
          case Wallaby.run(url) do
            {:ok, rendered} -> {:ok, Map.put(rendered, :fetcher, :wallaby)}
            # Fall back to whatever static gave us rather than failing the whole pipeline.
            {:error, _reason} -> {:ok, Map.put(static, :fetcher, :static)}
          end
      end
    end
  end
end
