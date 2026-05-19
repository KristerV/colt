defmodule Colt.Resources.Campaign.Changes.AdvanceStatus do
  @moduledoc """
  Sets `:status` only if the target is forward of the current value.
  Prevents re-running an earlier wizard step from regressing an already-running
  or completed campaign.
  """
  use Ash.Resource.Change

  @order [draft: 0, collecting: 1, enriching: 2]

  @impl true
  def change(changeset, opts, _context) do
    target = Keyword.fetch!(opts, :to)
    current = Ash.Changeset.get_attribute(changeset, :status)

    if rank(target) > rank(current) do
      Ash.Changeset.change_attribute(changeset, :status, target)
    else
      changeset
    end
  end

  defp rank(status), do: Keyword.get(@order, status, -1)
end
