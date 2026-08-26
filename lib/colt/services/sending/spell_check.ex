defmodule Colt.Services.Sending.SpellCheck do
  @moduledoc """
  Spell/typo check for a sequence being hand-edited in the writer, in one
  model call for the whole sequence (subject + every step body). Advisory
  only — the caller decides whether to block on the result.
  """

  alias Colt.Services.Ai.Complete

  @schema %{
    type: "object",
    additionalProperties: false,
    required: ["warnings"],
    properties: %{
      warnings: %{
        type: "array",
        items: %{
          type: "object",
          additionalProperties: false,
          required: ["position", "original", "suggestion"],
          properties: %{
            position: %{type: "string"},
            original: %{type: "string"},
            suggestion: %{type: "string"}
          }
        }
      }
    }
  }

  def run(fields, opts \\ []) do
    with {:ok, prompt} <- build_prompt(fields) do
      call(prompt, opts)
    end
  end

  defp build_prompt(fields) do
    body_parts =
      (fields[:bodies] || %{})
      |> Enum.sort_by(fn {pos, _text} -> pos end)
      |> Enum.map(fn {pos, text} -> {to_string(pos), text} end)

    parts =
      [{"subject", fields[:subject]} | body_parts]
      |> Enum.reject(fn {_pos, text} -> blank?(text) end)
      |> Enum.map(fn {pos, text} -> "[#{pos}]\n#{text}" end)

    if parts == [] do
      {:error, :nothing_to_check}
    else
      {:ok, Enum.join(parts, "\n\n")}
    end
  end

  defp blank?(nil), do: true
  defp blank?(text), do: String.trim(text) == ""

  defp call(prompt, opts) do
    case Complete.run(:smart, prompt,
           system: system_prompt(opts[:language]),
           response_format: :json,
           schema: @schema,
           temperature: 0.1,
           task: :spell_check,
           campaign_id: opts[:campaign_id],
           subject: opts[:subject]
         ) do
      {:ok, %{content: %{"warnings" => warnings}}} when is_list(warnings) ->
        {:ok, warnings}

      {:ok, _other} ->
        {:error, :spell_check_invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp system_prompt(language) do
    """
    You proofread a cold-outreach email sequence written in language "#{language || "en"}".
    Each block below is labeled with a position: "subject" for the shared
    subject line, or an integer for that follow-up step's body.

    Flag only genuine spelling/typo mistakes — misspelled words, wrong letters,
    doubled or missing letters, obvious autocorrect slips. Do NOT flag: style,
    tone, grammar choices, punctuation preference, casing, or phrasing you'd
    simply word differently. If a word could plausibly be a name, product, or
    intentional shorthand, leave it alone. Prefer zero warnings over a
    speculative one.

    For each real typo, report the position it's in, the exact original
    misspelled word/phrase as it appears in the text, and your suggested
    correction. Return {"warnings": []} if nothing is wrong.
    """
  end
end
