defmodule Colt.Accounts.User.Changes.MaybePromoteFirstAdmin do
  @moduledoc """
  If the users table is empty when this changeset runs, the new user is
  promoted to admin. Bootstraps the very first signup as the site admin.
  """

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.before_action(changeset, fn cs ->
      if Ash.count!(Colt.Accounts.User, authorize?: false) == 0 do
        Changeset.force_change_attribute(cs, :is_admin, true)
      else
        cs
      end
    end)
  end
end
