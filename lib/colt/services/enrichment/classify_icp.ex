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
    #{audience_clause(opts[:business_model])}ICP description:
    #{icp_description}
    #{learnings_clause(opts[:learnings])}
    Company summary:
    #{company_summary}

    Match unless the summary actively contradicts the ICP#{audience_tail(opts[:business_model])}. Return:
    {"match": true|false, "reason": "<one-sentence reason>"}.
    """

    case Complete.run(:smart, user,
           system: @system,
           response_format: :json,
           schema: @schema,
           campaign_id: opts[:campaign_id],
           subject: opts[:subject],
           task: "classify_icp",
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

  defp audience_clause(:b2b),
    do:
      "Audience: B2B only. The company MUST sell primarily to other businesses. If the summary describes a consumer-facing business (retail to individuals, restaurants, personal services, B2C e-commerce), REJECT.\n\n"

  defp audience_clause(:b2c),
    do:
      "Audience: B2C only. The company MUST sell primarily to consumers. If the summary describes a business that sells primarily to other businesses (B2B SaaS, wholesale, industrial supplier), REJECT.\n\n"

  defp audience_clause(_), do: ""

  defp learnings_clause(nil), do: ""
  defp learnings_clause([]), do: ""

  defp learnings_clause(learnings) when is_list(learnings) do
    {includes, excludes} =
      Enum.split_with(learnings, fn
        %{kind: :include} -> true
        _ -> false
      end)

    sections =
      [
        learnings_section(
          "Inclusions (positive traits — accept companies showing these even if other signals look borderline)",
          includes
        ),
        learnings_section(
          "Exclusions (disqualifying traits — reject companies showing these)",
          excludes
        )
      ]
      |> Enum.reject(&(&1 == ""))

    case sections do
      [] ->
        ""

      _ ->
        body = Enum.join(sections, "\n\n")

        """

        Additional ICP refinements (rules the user added after reviewing earlier classifications — treat with the same weight as the ICP above):
        #{body}
        """
    end
  end

  defp learnings_section(_label, []), do: ""

  defp learnings_section(label, items) do
    bullets = Enum.map_join(items, "\n", fn %{body: body} -> "- #{body}" end)
    "#{label}:\n#{bullets}"
  end

  defp audience_tail(:b2b), do: " or the audience constraint above"
  defp audience_tail(:b2c), do: " or the audience constraint above"
  defp audience_tail(_), do: ""
end
