defmodule Colt.Services.Enrichment.ValidateInMarkdown do
  @moduledoc """
  Per spec §6.9: discard hallucinated contacts. An email is valid if its
  local-part and domain occur in the markdown with at most 10 characters
  between them — catches obfuscations like `alice [at] acme.io`,
  `alice (at) acme.io`, `alice&#64;acme.io`, etc.

  Caller passes the haystack — concatenated markdown across the company's
  fetched pages — to keep IO out of this module.
  """

  def run(email, _haystack) when not is_binary(email) or email == "", do: {:ok, false}

  def run(email, haystack) when is_binary(haystack) do
    case String.split(email, "@", parts: 2) do
      [local, domain] when local != "" and domain != "" ->
        re = ~r/#{Regex.escape(local)}.{1,10}#{Regex.escape(domain)}/i
        {:ok, Regex.match?(re, haystack)}

      _ ->
        {:ok, false}
    end
  end

  def run(_, _), do: {:ok, false}
end
