defmodule Colt.Services.Enrichment.SummarizeLanding do
  @moduledoc """
  GLM 4.7 turns a landing page's markdown into one paragraph: what this
  company does, who it serves. Used downstream by ICP matching.
  """

  alias Colt.Services.Ai.Complete

  @system """
  You write a single neutral paragraph (max 60 words) describing what a company does and who it serves, based on text scraped from its landing page. No marketing fluff. No headings. No bullet points.
  """

  @max_input 8_000

  def run(markdown, opts \\ []) when is_binary(markdown) do
    trimmed = String.slice(markdown, 0, @max_input)

    case Complete.run(:cheap, "Landing page:\n\n#{trimmed}\n\nSummary:",
           system: @system,
           campaign_id: opts[:campaign_id],
           max_tokens: 220
         ) do
      {:ok, %{content: text}} -> {:ok, String.trim(text)}
      {:error, _} = err -> err
    end
  end
end
