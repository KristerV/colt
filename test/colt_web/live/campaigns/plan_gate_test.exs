defmodule ColtWeb.Campaigns.PlanGateTest do
  @moduledoc """
  The `:live_plan_required` on_mount hook gates the post-pricing campaign
  steps. Admins always pass (they never buy a package); unpaid users are
  bounced to /pricing so they can't skip the gate via the sidebar menu;
  pre-pricing steps stay open to everyone signed in.
  """
  use ColtWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Colt.Accounts.User
  alias Colt.Resources.Campaign

  defp create_user(email) do
    User
    |> Ash.Changeset.for_create(:seed, %{email: email}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp make_paid(user) do
    {:ok, user} =
      Colt.Accounts.apply_subscription(
        user,
        %{
          monthly_contact_capacity: 100,
          subscription_period_start: ~U[2026-05-01 00:00:00Z],
          subscription_period_end: ~U[2026-07-01 00:00:00Z],
          subscription_status: :active
        },
        authorize?: false
      )

    user
  end

  defp log_in(conn, user) do
    {:ok, token, _} = AshAuthentication.Jwt.token_for_user(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("user_token", token)
  end

  defp campaign_for(user) do
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)
    {:ok, c} = Campaign.set_icp(c, "B2B", "CTO", :b2b, actor: user)
    {:ok, c} = Campaign.set_market(c, :ee, actor: user)
    c
  end

  describe "post-pricing step (/icp)" do
    setup do
      # The first user in an empty table is auto-promoted to admin, so burn
      # that slot to ensure the subjects below are ordinary, non-admin users.
      _first_admin = create_user("first-admin@example.com")
      :ok
    end

    test "unpaid normal user is redirected to /pricing", %{conn: conn} do
      user = create_user("free@example.com")
      c = campaign_for(user)
      conn = log_in(conn, user)

      assert {:error, {:redirect, %{to: "/pricing"}}} =
               live(conn, ~p"/campaigns/#{c.id}/icp")
    end

    test "paid normal user reaches the step", %{conn: conn} do
      user = "paid@example.com" |> create_user() |> make_paid()
      c = campaign_for(user)
      conn = log_in(conn, user)

      assert {:ok, _view, _html} = live(conn, ~p"/campaigns/#{c.id}/icp")
    end
  end

  test "admin with no subscription reaches the step (never sees pricing)", %{conn: conn} do
    admin = create_user("admin@example.com")
    assert admin.is_admin
    assert User.paid?(admin), "admin should clear the paywall without a subscription"
    c = campaign_for(admin)
    conn = log_in(conn, admin)

    assert {:ok, _view, _html} = live(conn, ~p"/campaigns/#{c.id}/icp")
  end

  test "unpaid user can still reach pre-pricing steps (/filters)", %{conn: conn} do
    _first_admin = create_user("first-admin@example.com")
    user = create_user("free@example.com")
    c = campaign_for(user)
    conn = log_in(conn, user)

    assert {:ok, _view, _html} = live(conn, ~p"/campaigns/#{c.id}/filters")
  end
end
