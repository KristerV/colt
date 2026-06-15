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
  You pick the single best contact from a list of people at a company, given
  a target job title. Your job is to find someone in the SAME FUNCTION as the
  target — not just anyone at the company.

  The target may be a single title or a comma-separated list in order of
  importance ("Sales Manager, COO, CEO" means try Sales Manager first, fall
  back to COO, then CEO). Pick the highest-priority match that exists.

  Match by FUNCTION, generously, across seniority, synonyms, and languages:

  - Leadership target (CEO, Founder, Owner, Managing Director, COO, President):
    any top decision-maker counts. Estonian "juhataja"/"Juhatuse liige",
    Finnish "toimitusjohtaja", German "Geschäftsführer", Polish "Prezes
    Zarządu" all match.
  - Sales target (Head of Sales, Sales Manager, Sales Director, CSO): ANY
    sales role counts, including junior ones — "Sales Manager", "Sales
    Representative", "Account Manager", "Account Executive", "Business
    Development", "Sales Agent" are all fine matches. Be vague here: a sales
    rep is a perfectly good match for a "Head of Sales" target.
  - Marketing, Engineering/Tech, HR, Finance, etc.: same idea — match anyone
    whose function is the same as the target, at any seniority.

  Be vague, not stupid. Do NOT match across functions. For a Sales or CEO
  target, an unrelated specialist is NOT a match: e.g. "Construction
  Engineer", "Head of Electrical Works Department", "Project Engineer",
  "Site Supervisor", "Accountant", "Warehouse Manager" do NOT match a sales
  or leadership target. A CEO/owner is always an acceptable fallback for any
  business target, but a random department head is not.

  If, and only if, NO candidate is in the target function (and there is no
  CEO/owner to fall back to), return {"index": null}. Returning null is the
  correct, expected outcome when the company simply has no contact of the
  type we want — downstream this marks the company as "no contact found",
  which is fine. Do not force a wrong pick just to avoid null.

  If no target is provided, pick the most senior decision-maker (CEO,
  Founder, Managing Director > VP/Head > Director > Manager > IC).

  If multiple candidates are equally good, pick the lowest-numbered one.

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
    #{learnings_clause(opts[:learnings])}
    Candidates:
    #{listing}

    Return {"index": <0-based index of the best match>} or {"index": null}.
    """

    case Complete.run(:cheap, user,
           system: @system,
           response_format: :json,
           schema: @schema,
           campaign_id: opts[:campaign_id],
           subject: opts[:subject],
           task: "pick_best_contact",
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

  defp learnings_clause(nil), do: ""
  defp learnings_clause([]), do: ""

  defp learnings_clause(learnings) when is_list(learnings) do
    bullets = Enum.map_join(learnings, "\n", fn %{body: body} -> "- #{body}" end)

    """

    Contact-selection rules the user added after reviewing earlier picks —
    treat with the same weight as the target above. Avoid picking people who
    match these; if every candidate is ruled out by them, return null:
    #{bullets}
    """
  end
end
