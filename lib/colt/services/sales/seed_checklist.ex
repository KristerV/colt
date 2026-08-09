defmodule Colt.Services.Sales.SeedChecklist do
  @moduledoc """
  Fill a campaign's sales checklist with the starter set: Intro call → Demo
  booked → Proposal sent.

  Deliberately **not** run on mount. The checklist is optional — the funnel
  works fine without one — and an on-visit seed would resurrect the whole set
  every time someone cleared it on purpose. It runs only from the explicit
  "Use starter checklist" button on the empty state.
  """

  alias Colt.Resources.ChecklistItem

  @defaults ["Intro call", "Demo booked", "Proposal sent"]

  @doc "Returns `{:ok, items}` — the seeded items, in order."
  def run(campaign_id, opts \\ []) when is_binary(campaign_id) do
    actor = Keyword.get(opts, :actor)
    auth? = actor != nil

    @defaults
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {name, position}, {:ok, acc} ->
      case ChecklistItem.create(campaign_id, name, position, actor: actor, authorize?: auth?) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      other -> other
    end
  end
end
