defmodule Colt.Services.Sales.AutoEnter do
  @moduledoc """
  Auto-entry into the sales funnel from the sending machine. When a contact
  becomes interested (or call-ready), it drops into the funnel's **Now**
  bucket — no next action set yet — and a system `StatusEvent` records the
  entry.

  ## The one toggle

  `@triggers` is the single place that decides which sending outcomes pull a
  contact into the sales funnel. It ships as `[:interested, :call_ready]` — a
  call-ready contact is definitionally ready for a sales conversation. To make
  it interested-only, drop `:call_ready` from this list. Nothing else changes.
  """

  alias Colt.Services.Sales.EnterSalesFunnel

  @triggers [:interested, :call_ready]

  @doc "The sending outcomes that trigger auto-entry (see moduledoc)."
  def triggers, do: @triggers

  @doc "True when `outcome` should pull the contact into the sales funnel."
  def trigger?(outcome), do: outcome in @triggers

  @doc """
  Enter `contact_id` into the sales funnel. Idempotent — delegates to
  `EnterSalesFunnel`, so a contact a human already placed is left untouched.
  """
  def run(contact_id, opts \\ []) when is_binary(contact_id) do
    EnterSalesFunnel.run(contact_id, opts)
  end
end
