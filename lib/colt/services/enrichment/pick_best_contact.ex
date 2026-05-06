defmodule Colt.Services.Enrichment.PickBestContact do
  @moduledoc """
  Given a list of extracted person titles (and optionally a target job title),
  ask GLM 4.7 to pick the single best contact by index. Returns
  `{:ok, index | :none}`. One AI call per company.

  Rationale: replaces a per-title boolean classifier. Letting the model see
  the full list and choose one position is closer to how a human would read
  the page and avoids ties that need post-hoc resolution.
  """

  alias Colt.Services.Ai.Complete

  @system """
  You pick the single best contact from a list of people at a company.

  If a target title is provided, pick the closest match. Match generously:
  "Head of Engineering" matches "CTO", "VP Sales" matches "Head of Sales".
  A junior IC role does not match a leadership target.

  If no target title is provided, pick the most senior decision-maker (CEO,
  Founder, Managing Director > VP/Head > Director > Manager > IC).

  If multiple candidates are equally good, pick the lowest-numbered one.
  If none are appropriate, return null.

  Return JSON only.
  """

  @schema %{
    type: "object",
    additionalProperties: false,
    required: ["index"],
    properties: %{
      index: %{type: ["integer", "null"]}
    }
  }

  def run(target_title, titles, opts \\ [])

  def run(_target, [], _opts), do: {:ok, :none}

  def run(target_title, titles, opts) when is_list(titles) do
    listing =
      titles
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {t, i} -> "#{i}. #{t || "(no title)"}" end)

    user = """
    Target title: #{target_title || "(none — pick the most senior decision-maker)"}

    Candidates:
    #{listing}

    Return {"index": <0-based index of the best match>} or {"index": null}.
    """

    case Complete.run(:cheap, user,
           system: @system,
           response_format: :json,
           schema: @schema,
           campaign_id: opts[:campaign_id],
           max_tokens: 1500
         ) do
      {:ok, %{content: %{"index" => i}}} when is_integer(i) and i >= 0 and i < length(titles) ->
        {:ok, i}

      {:ok, _} ->
        {:ok, :none}

      {:error, _} = err ->
        err
    end
  end
end
