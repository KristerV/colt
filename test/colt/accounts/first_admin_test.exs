defmodule Colt.Accounts.FirstAdminTest do
  @moduledoc """
  The `MaybePromoteFirstAdmin` change is wired into both the magic-link
  sign-in/registration action and the `:seed` action. Testing the rule via
  `:seed` keeps the test free of token plumbing — the rule itself is what
  matters and it's the same change in both paths.
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
