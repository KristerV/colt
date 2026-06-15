defmodule Colt.Services.Enrichment.GenerateContactLearning do
  @moduledoc """
  Distill user feedback about a *wrong contact* into a short, generalised rule
  for the contact picker (`PickBestContact`). The user reviewed one contact the
  system auto-picked and explained why that person is the wrong one to reach;
  we turn it into a reusable role-selection rule so the picker avoids similar
  people (and prefers better ones) on the next company.

  The rule is *not* about this one person — it's the trait that ought to rule
  out (or in) any similar candidate.
  """

  alias Colt.Services.Ai.Complete

  @system """
  You turn user feedback into a single short rule about WHICH CONTACT to pick at a company, for an outreach tool that auto-selects one person to email.

  The user was shown the one contact the system picked and explained why that person is the wrong contact to reach out to. Produce ONE concise rule (max 20 words) that generalises the feedback so the picker avoids similar people, and prefers better ones, next time.

  Rules:
  - Write it as guidance about roles/functions ("Avoid X roles", "Prefer Y over Z"), never about this one person by name.
  - Generalise the trait. If the user says "this is a purchasing manager, I want someone who sells", the rule is "Avoid procurement/purchasing roles; prefer commercial or sales contacts".
  - If the user's reason is too vague to generalise, restate it cleanly without adding invented detail.
  - Plain text. No prefixes, no quotes, no trailing period.

  Return JSON only.
  """

  @schema %{
    type: "object",
    additionalProperties: false,
    required: ["rule"],
    properties: %{rule: %{type: "string"}}
  }

  def run(target_title, picked_title, user_reason, opts \\ [])
      when is_binary(user_reason) do
    user = """
    Target job title we want: #{blank(target_title, "(none specified)")}

    The contact the system picked (the wrong one): #{blank(picked_title, "(no title)")}

    User's reason it's the wrong contact:
    #{user_reason}

    Produce one short generalised contact-selection rule. Return {"rule": "<rule>"}.
    """

    case Complete.run(:smart, user,
           system: @system,
           response_format: :json,
           schema: @schema,
           campaign_id: opts[:campaign_id],
           subject: opts[:subject],
           task: "generate_contact_learning",
           max_tokens: 500,
           temperature: 0.2
         ) do
      {:ok, %{content: %{"rule" => rule}}} when is_binary(rule) ->
        {:ok, String.trim(rule)}

      {:ok, _} ->
        {:error, :bad_response}

      {:error, _} = err ->
        err
    end
  end

  defp blank(nil, fallback), do: fallback
  defp blank("", fallback), do: fallback
  defp blank(value, _fallback), do: value
end
