defmodule Colt.Services.Enrichment.ValidateInMarkdown do
  @moduledoc """
  Per spec §6.9: discard hallucinated contacts. An email is valid if its
  string occurs (case-insensitive) somewhere in the company's stored page
  markdown.

  Caller passes the haystack — concatenated markdown across the company's
  fetched pages — to keep IO out of this module.
  """

  def run(email, _haystack) when not is_binary(email) or email == "", do: {:ok, false}

  def run(email, haystack) when is_binary(haystack) do
    needle = String.downcase(email)
    hay = String.downcase(haystack)
    {:ok, String.contains?(hay, needle)}
  end

  def run(_, _), do: {:ok, false}
end
