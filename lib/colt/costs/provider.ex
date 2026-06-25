defmodule Colt.Costs.Provider do
  @moduledoc """
  Maps an `ApiCall` (its routing `provider` + `model` id) to the *end* provider
  — the company actually serving the model — for cost breakdowns.

  OpenRouter is a gateway: the real provider is encoded as the slug left of the
  `/` in the model id (`"google/gemini-3.5-flash"` → Google, `"z-ai/glm-4.7"` →
  GLM). Google CSE is itself the end provider.
  """

  @vendor_labels %{
    "google" => "Google (Gemini)",
    "z-ai" => "GLM (z-ai)",
    "anthropic" => "Anthropic",
    "openai" => "OpenAI",
    "x-ai" => "xAI (Grok)",
    "deepseek" => "DeepSeek",
    "meta-llama" => "Meta (Llama)",
    "mistralai" => "Mistral",
    "qwen" => "Qwen",
    "moonshotai" => "Moonshot"
  }

  @doc """
  Human label for the end provider behind a call.

      iex> Colt.Costs.Provider.label(:openrouter, "google/gemini-3.5-flash")
      "Google (Gemini)"
      iex> Colt.Costs.Provider.label(:google_cse, nil)
      "Google Search"
  """
  def label(:google_cse, _model), do: "Google Search"

  def label(:openrouter, model) when is_binary(model) do
    case String.split(model, "/", parts: 2) do
      [vendor, _rest] -> Map.get(@vendor_labels, vendor, prettify(vendor))
      _ -> "OpenRouter"
    end
  end

  def label(provider, _model) when is_atom(provider), do: prettify(to_string(provider))
  def label(_provider, _model), do: "—"

  defp prettify(slug) do
    slug
    |> String.split(["-", "_"])
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
