defmodule Colt.Services.Enrichment.Freshness do
  @moduledoc """
  Cache decisions per spec §7. Each predicate answers "should we redo this
  step, or reuse what's on disk?". Workers call these before doing work and
  short-circuit (with a `stage:done` broadcast for UI continuity) when fresh.

  Window: 30 days.
  """

  alias Colt.Resources.{Company, Page, Person}

  @ttl_days 30

  @doc """
  True if the company-level enrichment (website / summary) is still warm.
  """
  def company_fresh?(%Company{last_enriched_at: nil}), do: false

  def company_fresh?(%Company{last_enriched_at: ts}) do
    DateTime.diff(DateTime.utc_now(), ts, :day) < @ttl_days
  end

  @doc """
  True if the page was fetched within the TTL and has markdown.
  """
  def page_fresh?(%Page{fetched_at: nil}), do: false
  def page_fresh?(%Page{markdown: nil}), do: false

  def page_fresh?(%Page{fetched_at: ts}) do
    DateTime.diff(DateTime.utc_now(), ts, :day) < @ttl_days
  end

  @doc """
  Reusable summary present on the company.
  """
  def has_summary?(%Company{ai_summary: s}) when is_binary(s) and byte_size(s) > 0, do: true
  def has_summary?(_), do: false

  @doc """
  Persons already extracted for this company (across any campaign).
  """
  def existing_persons(%Company{id: id}) do
    case Person.for_company(id) do
      {:ok, list} -> list
      _ -> []
    end
  end
end
