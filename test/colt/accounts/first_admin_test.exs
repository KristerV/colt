defmodule Colt.Accounts.FirstAdminTest do
  @moduledoc """
  The `MaybePromoteFirstAdmin` change is wired into the `:seed` action
  (magic-link registration is closed, so seeding is the only create path).
  """

  use Colt.DataCase, async: false

  alias Colt.Accounts.User

  defp seed_user(email) do
    User
    |> Ash.Changeset.for_create(:seed, %{email: email}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  test "first user is promoted to admin" do
    user = seed_user("first@example.com")
    assert user.is_admin == true
  end

  test "second user is not promoted" do
    seed_user("first@example.com")
    second = seed_user("second@example.com")
    assert second.is_admin == false
  end
end
