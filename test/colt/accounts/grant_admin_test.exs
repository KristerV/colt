defmodule Colt.Accounts.GrantAdminTest do
  use Colt.DataCase, async: false

  alias Colt.Accounts.User

  defp seed_user(email) do
    User
    |> Ash.Changeset.for_create(:seed, %{email: email}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  test "promotes a plain user to admin" do
    # First user auto-promotes; seed a second so this one starts non-admin.
    seed_user("first@example.com")
    user = seed_user("second@example.com")
    refute user.is_admin

    {:ok, promoted} = Colt.Accounts.grant_admin(user, authorize?: false)

    assert promoted.is_admin
  end

  test "is one-directional — the action accepts no input at all" do
    seed_user("first@example.com")
    user = seed_user("second@example.com")

    # is_admin isn't in `accept`, so there is no way to pass false through
    # this action — the only path to :grant_admin is always true.
    assert {:error, %Ash.Error.Invalid{}} =
             user
             |> Ash.Changeset.for_update(:grant_admin, %{is_admin: false}, authorize?: false)
             |> Ash.update()
  end
end
