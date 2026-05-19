defmodule Colt.Services.Enrichment.GenerateIcpLearning do
  @moduledoc """
  Distill user feedback on one specific company into a short, generalised
  rule that refines the ICP at classify-time. Works in both directions:

    * `:exclude` — the company was classified as a match but the user says
      it's NOT a good fit → produce a rule that disqualifies similar
      companies next time.
    * `:include` — the company was rejected but the user says it IS a good
      fit → produce a rule that accepts similar companies next time.

  The rule is *not* about this one company — it's the trait that ought to
  qualify or disqualify any similar company.
  """

  alias Colt.Services.Ai.Complete

  @system_exclude """
  You turn user feedback into a single short exclusion rule for an Ideal Customer Profile filter.

  The user reviewed one company that was classified as a match and explained why it actually is NOT a good fit. Your job is to read the ICP, the company summary, and the user's reason, and produce ONE concise rule (max 20 words) that generalises the feedback so similar companies would be filtered out next time.

  Rules:
  - Write the rule as a constraint ("Exclude X" or "Must not be Y" or "Reject when Z"), not as a description of this company.
  - Generalise the trait. If the user says "they are just resellers", the rule is "Exclude pure resellers / distributors" — not "Exclude Acme Trading OÜ".
  - If the user's reason is too vague to generalise, restate it cleanly without adding invented detail.
  - Plain text. No prefixes, no quotes, no trailing period.

  Return JSON only.
  """

  @system_include """
  You turn user feedback into a single short inclusion rule for an Ideal Customer Profile filter.

  The user reviewed one company that was classified as NOT a match and explained why it actually IS a good fit. Your job is to read the ICP, the company summary, and the user's reason, and produce ONE concise rule (max 20 words) that generalises the feedback so similar companies would be accepted next time.

  Rules:
  - Write the rule as a positive trait that qualifies a company ("Include X" or "Accept when Y" or "Treat Z as a match"), not as a description of this one company.
  - Generalise the trait. If the user says "they manufacture pumps in-house, that counts as a manufacturer", the rule is "Include in-house manufacturers even if their site emphasises distribution" — not "Include Acme Pumps OÜ".
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

  def run(icp_description, company_summary, user_reason, kind, opts \\ [])
      when is_binary(icp_description) and is_binary(company_summary) and is_binary(user_reason) and
             kind in [:exclude, :include] do
    user = """
    ICP description:
    #{icp_description}

    Company summary:
    #{company_summary}

    User's reason for #{verb(kind)} this company:
    #{user_reason}

    Produce one short generalised #{kind_label(kind)} rule. Return {"rule": "<rule>"}.
    """

    case Complete.run(:smart, user,
           system: system_prompt(kind),
           response_format: :json,
           schema: @schema,
           campaign_id: opts[:campaign_id],
           subject: opts[:subject],
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

  defp system_prompt(:exclude), do: @system_exclude
  defp system_prompt(:include), do: @system_include

  defp verb(:exclude), do: "rejecting"
  defp verb(:include), do: "accepting"

  defp kind_label(:exclude), do: "exclusion"
  defp kind_label(:include), do: "inclusion"
end
