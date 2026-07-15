defmodule Colt.Services.Enrichment.ContactRungs do
  @moduledoc """
  The contact ladder: **owner → title → generic**, in that fixed order.

  The order is not user-editable and deliberately so — it's strictly decreasing
  in value (a named owner beats a named role beats an unnamed inbox), so the only
  real choice is which rungs you're willing to land on. The campaign's three
  `reach_*?` booleans say that; this module says what to try next.

  Keeping the order here means the ladder is stated once. `ResolveContact` walks
  it forward, and `ExtractContacts` re-enters it after the title rung fails —
  neither needs to know the shape.

  See `docs/specs/contact-acquisition.md` §4.
  """

  @order [:owner, :title, :generic]

  @doc "The first rung to try, or `:none` if the campaign enabled nothing."
  def first(campaign), do: next_from(campaign, @order)

  @doc """
  The rung to try after `rung` failed to produce an address, or `:none` when the
  ladder is exhausted.
  """
  def after_rung(campaign, rung) do
    case Enum.split_while(@order, &(&1 != rung)) do
      {_, [^rung | rest]} -> next_from(campaign, rest)
      _ -> :none
    end
  end

  defp next_from(campaign, rungs) do
    Enum.find(rungs, :none, &enabled?(campaign, &1))
  end

  defp enabled?(campaign, :owner), do: campaign.reach_owner?
  defp enabled?(campaign, :title), do: campaign.reach_title?
  defp enabled?(campaign, :generic), do: campaign.reach_generic?
end
