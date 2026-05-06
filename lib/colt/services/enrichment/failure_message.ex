defmodule Colt.Services.Enrichment.FailureMessage do
  @moduledoc """
  Translates raw worker errors into a user-friendly message + technical detail
  pair. The user message lands in `CampaignCompany.rejection_reason`; the raw
  string lands in `CampaignCompany.failure_detail` (admin-only in the UI).
  """

  @type stage :: :website | :icp | :contact

  @doc """
  Build `{user_message, technical_detail}` for the given stage and raw error.

  `raw` may be a string, atom, exception, or arbitrary term — we normalise to
  a string for the detail and pattern-match for the user message.
  """
  @spec run(stage(), any()) :: {String.t(), String.t()}
  def run(stage, raw) do
    detail = to_detail(raw)
    {prefix(stage) <> ": " <> classify(detail), detail}
  end

  defp prefix(:website), do: "Couldn't analyze website"
  defp prefix(:icp), do: "Couldn't match against ICP"
  defp prefix(:contact), do: "Couldn't extract contact"

  # Heuristic mapping. Order matters — most specific first.
  defp classify(d) do
    cond do
      String.contains?(d, "model returned non-JSON") -> "AI gave an unparseable answer"
      String.contains?(d, "model returned empty") -> "AI didn't return an answer"
      String.contains?(d, "openrouter http 408") -> "AI service timed out"
      String.contains?(d, "openrouter http 429") -> "AI service rate-limited us"
      String.contains?(d, "openrouter http 4") -> "AI service rejected the request"
      String.contains?(d, "openrouter http 5") -> "AI service is having trouble"
      String.contains?(d, "no landing markdown") -> "couldn't read website content"
      String.contains?(d, "no contact-page markdown") -> "couldn't read contact page"
      String.contains?(d, "timeout") -> "network timed out"
      String.contains?(d, "TransportError") -> "network error reaching AI service"
      String.contains?(d, "Jason.DecodeError") -> "AI gave an unparseable answer"
      true -> "something went wrong"
    end
  end

  defp to_detail(raw) when is_binary(raw), do: raw
  defp to_detail(%{__exception__: true} = e), do: Exception.message(e)
  defp to_detail(other), do: inspect(other)
end
