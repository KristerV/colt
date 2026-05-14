defmodule Colt.Services.Enrichment.GenerateIcpLearning do
  @moduledoc """
  Distill a user's "not a good fit" feedback on one specific company into a
  short, generalised exclusion rule that can be appended to the ICP at
  classify-time. The rule is *not* about this one company — it's the trait
  that ought to disqualify any similar company.
  """

  alias Colt.Services.Ai.Complete

  @system """
  You turn user feedback into a single short exclusion rule for an Ideal Customer Profile filter.

  The user reviewed one company that was classified as a match and explained why it actually is NOT a good fit. Your job is to read the ICP, the company summary, and the user's reason, and produce ONE concise rule (max 20 words) that generalises the feedback so similar companies would be filtered out next time.

  Rules:
  - Write the rule as a constraint ("Exclude X" or "Must not be Y" or "Reject when Z"), not as a description of this company.
  - Generalise the trait. If the user says "they are just resellers", the rule is "Exclude pure resellers / distributors" — not "Exclude Acme Trading OÜ".
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

  def run(icp_description, company_summary, user_reason, opts \\ [])
      when is_binary(icp_description) and is_binary(company_summary) and is_binary(user_reason) do
    user = """
    ICP description:
    #{icp_description}

    Company summary:
    #{company_summary}

    User's reason for rejecting this company:
    #{user_reason}

    Produce one short generalised exclusion rule. Return {"rule": "<rule>"}.
    """

    case Complete.run(:smart, user,
           system: @system,
           response_format: :json,
           schema: @schema,
           campaign_id: opts[:campaign_id],
           task: "generate_icp_learning",
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
end
