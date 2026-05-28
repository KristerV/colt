defmodule Colt.Resources.Campaign.Changes.CapacityGuard do
  @moduledoc """
  Rejects raising `:target_contact_count` beyond the owner's remaining
  monthly enrichment capacity. Already-enriched contacts are never
  retroactively gated — the cap is on forward enrichment volume only:

      new_target <= done_count + remaining_capacity

  Admins bypass.
  """
  use Ash.Resource.Change

  alias Colt.Accounts.User

  @impl true
  def change(changeset, _opts, %{actor: %{is_admin: true}}), do: changeset

  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &guard/1)
  end

  defp guard(changeset) do
    new_target = Ash.Changeset.get_attribute(changeset, :target_contact_count)

    cond do
      not is_integer(new_target) ->
        changeset

      is_nil(changeset.data.id) ->
        changeset

      true ->
        with {:ok, campaign} <-
               Ash.load(changeset.data, [:done_count], authorize?: false),
             {:ok, owner} <-
               Ash.get(User, campaign.owner_id,
                 load: [:remaining_capacity],
                 authorize?: false
               ) do
          done = campaign.done_count || 0
          remaining = max(owner.remaining_capacity || 0, 0)
          max_target = done + remaining

          if new_target > max_target do
            Ash.Changeset.add_error(
              changeset,
              field: :target_contact_count,
              message:
                "over_capacity: monthly cap is #{owner.monthly_contact_capacity}, " <>
                  "#{remaining} contacts remaining this period — target capped at #{max_target}"
            )
          else
            changeset
          end
        else
          _ -> changeset
        end
    end
  end
end
