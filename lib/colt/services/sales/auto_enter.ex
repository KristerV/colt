defmodule Colt.Services.Sales.AutoEnter do
  @moduledoc """
  Auto-entry into the sales funnel from the sending machine. When a contact
  becomes interested (or call-ready), it drops into the first active stage
  and a system `StatusEvent` records the entry.

  ## The one toggle

  `@triggers` is the single place that decides which sending outcomes pull a
  contact into the sales funnel. It ships as `[:interested, :call_ready]` — a
  call-ready contact is definitionally ready for a sales conversation. To make
  it interested-only, drop `:call_ready` from this list. Nothing else changes.
  """

  alias Colt.Resources.SalesStage
  alias Colt.Services.Sales.{EnterSalesFunnel, SeedStages}

  @triggers [:interested, :call_ready]

  @doc "The sending outcomes that trigger auto-entry (see moduledoc)."
  def triggers, do: @triggers

  @doc "True when `outcome` should pull the contact into the sales funnel."
  def trigger?(outcome), do: outcome in @triggers

  @doc """
  Enter `contact_id` into the campaign's first active stage (seeding the
  starter stages first if the campaign has none). Idempotent — delegates to
  `EnterSalesFunnel`, so a contact a human already placed is left untouched.
  """
  def run(contact_id, campaign_id, opts \\ [])
      when is_binary(contact_id) and is_binary(campaign_id) do
    with {:ok, stages} <- SeedStages.run(campaign_id, opts),
         {:ok, stage} <- first_active(stages) do
      EnterSalesFunnel.run(contact_id, stage.id, opts)
    end
  end

  defp first_active(stages) do
    case Enum.find(stages, &(&1.kind == :active)) do
      %SalesStage{} = stage -> {:ok, stage}
      _ -> {:error, :no_active_stage}
    end
  end
end
