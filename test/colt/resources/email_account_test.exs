defmodule Colt.Resources.EmailAccountTest do
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.EmailAccount

  defp seed_user(email \\ "owner@example.com") do
    User
    |> Ash.Changeset.for_create(:seed, %{email: email}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp seed_account(user, attrs \\ %{}) do
    base = %{
      provider: :imap,
      address: "robert@liidid.ee",
      display_name: nil,
      nylas_grant_id: "grant-#{System.unique_integer([:positive])}",
      tz: "Europe/Tallinn"
    }

    EmailAccount.create_from_nylas(
      Map.get(base, :provider),
      Map.get(base, :address),
      Map.get(attrs, :display_name, base.display_name),
      base.nylas_grant_id,
      base.tz,
      actor: user
    )
  end

  test "update_details sets the sender display name" do
    user = seed_user()
    {:ok, account} = seed_account(user)

    {:ok, updated} = EmailAccount.update_details(account, "Robert Kuusk", actor: user)

    assert updated.display_name == "Robert Kuusk"
  end

  test "update_details can clear the display name back to nil" do
    user = seed_user()
    {:ok, account} = seed_account(user, %{display_name: "Robert Kuusk"})

    {:ok, updated} = EmailAccount.update_details(account, nil, actor: user)

    assert updated.display_name == nil
  end

  test "policy: another user cannot edit your account name" do
    _bootstrap = seed_user("admin@example.com")
    me = seed_user("me@example.com")
    other = seed_user("other@example.com")

    {:ok, account} = seed_account(me)

    assert {:error, _} = EmailAccount.update_details(account, "Hacked", actor: other)
  end
end
