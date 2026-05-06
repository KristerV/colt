defmodule Colt.Services.Enrichment.PickContactPaths do
  @moduledoc """
  From the company's nav-extracted paths, pick up to 3 most likely to host
  named contacts. A heuristic prefilter narrows to plausible paths first;
  GLM 4.7 ranks the survivors. Returns `{:ok, [path]}`.
  """

  alias Colt.Services.Ai.Complete

  @keywords ~w(contact team about people staff kontakt meeskond yhteystiedot henkilosto tietoa)

  @system """
  Given paths from a company website, pick at most 3 most likely to list NAMED human contacts (founders, team, leadership, contact info). Return JSON only.
  """

  @schema %{
    type: "object",
    additionalProperties: false,
    required: ["paths"],
    properties: %{
      paths: %{
        type: "array",
        maxItems: 3,
        items: %{type: "string"}
      }
    }
  }

  def run(nav_links, opts \\ []) when is_list(nav_links) do
    candidates = prefilter(nav_links)

    cond do
      candidates == [] ->
        {:ok, []}

      length(candidates) <= 3 ->
        {:ok, Enum.map(candidates, & &1.path)}

      true ->
        rank(candidates, opts)
    end
  end

  defp prefilter(links) do
    Enum.filter(links, fn %{path: p, title: t} ->
      haystack = String.downcase("#{p} #{t || ""}")
      Enum.any?(@keywords, &String.contains?(haystack, &1))
    end)
  end

  defp rank(candidates, opts) do
    listing =
      candidates
      |> Enum.take(20)
      |> Enum.map_join("\n", fn %{path: p, title: t} -> "- #{p}  (#{t || ""})" end)

    user = """
    Paths:
    #{listing}

    Pick at most 3 paths most likely to list NAMED humans. Return {"paths": ["/...", ...]}.
    """

    case Complete.run(:cheap, user,
           system: @system,
           response_format: :json,
           schema: @schema,
           campaign_id: opts[:campaign_id],
           max_tokens: 1500
         ) do
      {:ok, %{content: %{"paths" => paths}}} when is_list(paths) ->
        {:ok, paths |> Enum.filter(&is_binary/1) |> Enum.take(3)}

      {:ok, _} ->
        {:ok, []}

      {:error, _} = err ->
        err
    end
  end
end
