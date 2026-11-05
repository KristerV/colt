defmodule Colt.Accounts.ClosedRegistrationTest do
  use Colt.DataCase, async: false
  alias Colt.Accounts.User
  alias AshAuthentication.{Info, Strategy}

  test "existing user signs in; unknown email gets no account" do
    user =
      User
      |> Ash.Changeset.for_create(:seed, %{email: "known@example.com"})
      |> Ash.create!(authorize?: false)

    strategy = Info.strategy!(User, :magic_link)

    {:ok, token} = Strategy.MagicLink.request_token_for(strategy, user)
    assert {:ok, signed_in} = Strategy.action(strategy, :sign_in, %{"token" => token})
    assert signed_in.id == user.id

    assert :ok = Strategy.action(strategy, :request, %{"email" => "stranger@example.com"})
    assert {:error, _} = Ash.get(User, [email: "stranger@example.com"], authorize?: false)
  end
end
