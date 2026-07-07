defmodule Colt.Services.Sales.SeedStages do
  @moduledoc """
  Idempotently seed a campaign's sales funnel with the starter stage set on
  first visit: Interested → Demo → Proposal, plus the Won / Lost exits. A
  no-op once any stage exists — the user's edits are never clobbered.
  """

  alias Colt.Resources.SalesStage

  @defaults [
    %{name: "Interested", position: 0, kind: :active},
    %{name: "Demo", position: 1, kind: :active},
    %{name: "Proposal", position: 2, kind: :active},
    %{name: "Won", position: 3, kind: :won},
    %{name: "Lost", position: 4, kind: :lost}
  ]

  @doc "Returns `{:ok, stages}` — the full ordered stage list for the campaign."
  def run(campaign_id, opts \\ []) when is_binary(campaign_id) do
    actor = Keyword.get(opts, :actor)
    auth? = actor != nil

    with {:ok, existing} <-
           SalesStage.list_for_campaign(campaign_id, actor: actor, authorize?: auth?) do
      case existing do
        [] -> seed(campaign_id, actor, auth?)
        stages -> {:ok, stages}
      end
    end
  end

  defp seed(campaign_id, actor, auth?) do
    Enum.reduce_while(@defaults, {:ok, []}, fn attrs, {:ok, acc} ->
      case SalesStage.create(campaign_id, attrs.name, attrs.position, %{kind: attrs.kind},
             actor: actor,
             authorize?: auth?
           ) do
        {:ok, stage} -> {:cont, {:ok, [stage | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, stages} -> {:ok, Enum.reverse(stages)}
      other -> other
    end
  end
end
