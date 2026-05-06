defmodule Colt.Services.Enrichment.MatchTitles do
  @moduledoc """
  Given a target job title and a list of extracted titles, return a parallel
  list of booleans. One AI call per company (batched), not per row, per spec §6.9.
  """

  alias Colt.Services.Ai.Complete

  @system """
  You decide whether each extracted job title matches a target title. Match generously: a "Head of Engineering" matches "CTO"; a "VP Sales" matches "Head of Sales". A junior IC role does not match a leadership target. Return JSON only.
  """

  def run(target_title, titles, opts \\ [])

  def run(_target, [], _opts), do: {:ok, []}

  def run(target_title, titles, opts) when is_binary(target_title) and is_list(titles) do
    listing =
      titles
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {t, i} -> "#{i}. #{t || ""}" end)

    schema = %{
      type: "object",
      additionalProperties: false,
      required: ["matches"],
      properties: %{
        matches: %{
          type: "array",
          minItems: length(titles),
          maxItems: length(titles),
          items: %{type: "boolean"}
        }
      }
    }

    user = """
    Target title: #{target_title}

    Candidate titles:
    #{listing}

    Return {"matches": [bool, bool, ...]} of the same length as the candidate list.
    """

    case Complete.run(:cheap, user,
           system: @system,
           response_format: :json,
           schema: schema,
           campaign_id: opts[:campaign_id],
           max_tokens: 1500
         ) do
      {:ok, %{content: %{"matches" => bs}}} when is_list(bs) and length(bs) == length(titles) ->
        {:ok, Enum.map(bs, &(!!&1))}

      {:ok, _} ->
        {:ok, List.duplicate(false, length(titles))}

      {:error, _} = err ->
        err
    end
  end
end
