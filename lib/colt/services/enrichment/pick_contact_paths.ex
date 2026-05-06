defmodule Colt.Services.Enrichment.PickContactPaths do
  @moduledoc """
  From a list of paths on a company website, ask GLM 4.7 to pick up to 3
  most likely to list named contacts (people, offices, "contact us", team).
  Multilingual — the AI handles language variants better than a keyword list.
  Returns `{:ok, [path]}`.
  """

  alias Colt.Services.Ai.Complete

  @system """
  You pick up to 3 paths from a company website that are most likely to list NAMED human contacts.

  Look for paths or anchor text suggesting:
  - "contact" pages (any language: contact, kontakt, contacto, contatti, võta ühendust, yhteystiedot, …)
  - "team" / "people" / "staff" / "leadership" / "about us" / "founders"
  - "offices" / "locations" / "branches" (any language: offices, kontorid, kontor, sucursales, oficinas, toimipisteet, …)
  - location/city pages under a contact or offices section (these often list per-office staff)

  Skip:
  - product categories, blog posts, news, careers/jobs (unless clearly leadership-related), legal pages, login/signup, language switchers, wishlists, search.

  If multiple candidates fit, prefer hub pages (e.g. "/contact", "/offices") over individual sub-pages.

  Return JSON only.
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

  @max_listed 40

  def run(nav_links, opts \\ []) when is_list(nav_links) do
    case Enum.take(nav_links, @max_listed) do
      [] -> {:ok, []}
      candidates -> rank(candidates, opts)
    end
  end

  defp rank(candidates, opts) do
    listing =
      candidates
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
           task: "pick_contact_paths",
           max_tokens: 4000
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
