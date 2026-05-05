defmodule Colt.Services.Enrichment.ClassifyIcp do
  @moduledoc """
  Claude Sonnet 4.5: given an ICP description and a company summary, decide
  match. Returns `{:ok, %{match: bool, reason: string}}`.
  """

  alias Colt.Services.Ai.Complete

  @system """
  You decide whether a company matches a user-described Ideal Customer Profile (ICP).
  Be strict. A vague match is not a match. Return JSON only.
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

    Decide: {"match": true|false, "reason": "<one-sentence reason>"}.
    """

    case Complete.run(:smart, user,
           system: @system,
           response_format: :json,
           schema: @schema,
           campaign_id: opts[:campaign_id],
           max_tokens: 200,
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
