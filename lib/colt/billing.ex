defmodule Colt.Billing do
  @moduledoc """
  The plan catalogue. Stripe is the source of truth for what a client actually
  pays; the app only ever stores the resulting `monthly_contact_capacity`, so
  the plan *name* and its list price have to be looked up from capacity.

  Configured under `config :colt, Colt.Billing, plans: [...]` so the admin views
  and (later) the pricing grid read one list instead of hardcoding labels.
  """

  @doc """
  The configured plans, cheapest first.
  """
  def plans do
    Application.get_env(:colt, __MODULE__, [])
    |> Keyword.get(:plans, [])
    |> Enum.sort_by(& &1.capacity)
  end

  @doc """
  The plan matching a monthly contact capacity, or `nil` for a user on no plan
  (or on a custom capacity we never sold as a package).
  """
  def plan_for(capacity) when is_integer(capacity) and capacity > 0 do
    Enum.find(plans(), &(&1.capacity == capacity))
  end

  def plan_for(_), do: nil

  @doc """
  Display label for a capacity: the plan name, or the bare capacity when it
  doesn't match a package. `nil` when the user has no capacity at all.
  """
  def plan_label(capacity) when is_integer(capacity) and capacity > 0 do
    case plan_for(capacity) do
      %{name: name} -> name
      nil -> "custom #{capacity}"
    end
  end

  def plan_label(_), do: nil

  @doc """
  Monthly list price in EUR for a capacity, or 0 when it isn't a known package.
  """
  def monthly_eur(capacity) do
    case plan_for(capacity) do
      %{eur: eur} -> eur
      nil -> 0
    end
  end
end
