defmodule Colt.Services.Enrichment.ExtractContacts do
  @moduledoc """
  Claude Sonnet 4.5 over concatenated contact-page markdown. Returns ALL
  named people found, not only title-matchers — title matching is a separate
  cheaper step.

  Output: `{:ok, [%{name, title, email, phone}]}`.
  """

  alias Colt.Services.Ai.Complete

  @system """
  Extract every NAMED human contact mentioned in the page text. Skip generic mailboxes (info@, contact@, sales@), skip companies, skip pure phone-number entries with no name. Return JSON only.
  """

  @schema %{
    type: "object",
    additionalProperties: false,
    required: ["people"],
    properties: %{
      people: %{
        type: "array",
        items: %{
          type: "object",
          additionalProperties: false,
          required: ["name", "title", "email", "phone"],
          properties: %{
            name: %{type: ["string", "null"]},
            title: %{type: ["string", "null"]},
            email: %{type: ["string", "null"]},
            phone: %{type: ["string", "null"]}
          }
        }
      }
    }
  }

  @max_input 100_000

  def run(markdown, opts \\ []) when is_binary(markdown) do
    trimmed = String.slice(markdown, 0, @max_input)

    case Complete.run(:smart, "Page text:\n\n#{trimmed}\n\nReturn the JSON.",
           system: @system,
           response_format: :json,
           schema: @schema,
           campaign_id: opts[:campaign_id],
           max_tokens: 16_000,
           temperature: 0.0
         ) do
      {:ok, %{content: %{"people" => people}}} when is_list(people) ->
        {:ok, Enum.map(people, &normalise/1)}

      {:ok, _} ->
        {:ok, []}

      {:error, _} = err ->
        err
    end
  end

  defp normalise(p) do
    %{
      name: blank_to_nil(p["name"]),
      title: blank_to_nil(p["title"]),
      email: p["email"] |> blank_to_nil() |> downcase(),
      phone: blank_to_nil(p["phone"])
    }
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      v -> v
    end
  end

  defp blank_to_nil(_), do: nil

  defp downcase(nil), do: nil
  defp downcase(s), do: String.downcase(s)
end
