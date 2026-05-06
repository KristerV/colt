defmodule Colt.Services.Enrichment.ClassifyIcp do
  @moduledoc """
  Claude Sonnet 4.5: given an ICP description and a company summary, decide
  match. Returns `{:ok, %{match: bool, reason: string}}`.
  """

  alias Colt.Services.Ai.Complete

  @system """
  You decide whether a company is a plausible target customer for a user-described Ideal Customer Profile (ICP).

  The ICP describes characteristics the buyer should have (industry, business model, what they sell or do, structural traits like having offices or employees). Treat it as a filter that excludes companies whose summary actively contradicts the ICP — NOT as a content match between the ICP text and the summary text.

  Default to MATCH. Silence in the summary is not contradiction. A company summary that doesn't mention a trait (offices, employees, regions served, etc.) almost always still has that trait — most companies do. Only reject when the summary describes the company in a way that makes the ICP impossible or implausible.

  Examples:
  - ICP: "companies with offices". Summary describes a normal industrial supplier or trade-show participant. → MATCH (they almost certainly have an office; nothing contradicts).
  - ICP: "companies with offices". Summary describes a one-person fully-remote freelance consultancy with no premises. → REJECT (contradicts).
  - ICP: "B2B SaaS companies". Summary describes a brick-and-mortar restaurant. → REJECT (industry contradicts).
  - ICP: "B2B SaaS companies". Summary doesn't say B2B vs B2C but describes an enterprise software product. → MATCH (no contradiction; product type fits).

  Be lenient. The ICP is a buyer-targeting filter, not a content keyword search. Reject only on clear contradiction.

  Return JSON only.
  """

  @schema %{
    type: "object",
    additionalProperties: false,
    required: ["match", "reason"],
    properties: %{
      match: %{type: "boolean"},
      reason: %{type: "string"}
    }
  }

  def run(icp_description, company_summary, opts \\ [])
      when is_binary(icp_description) and is_binary(company_summary) do
    user = """
    ICP description:
    #{icp_description}

    Company summary:
    #{company_summary}

    Match unless the summary actively contradicts the ICP. Return:
    {"match": true|false, "reason": "<one-sentence reason>"}.
    """

    case Complete.run(:smart, user,
           system: @system,
           response_format: :json,
           schema: @schema,
           campaign_id: opts[:campaign_id],
           max_tokens: 1500,
           temperature: 0.0
         ) do
      {:ok, %{content: %{"match" => m, "reason" => r}}} ->
        {:ok, %{match: !!m, reason: r}}

      {:ok, _} ->
        {:error, :bad_response}

      {:error, _} = err ->
        err
    end
  end
end
