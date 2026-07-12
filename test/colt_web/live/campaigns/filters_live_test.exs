defmodule ColtWeb.Campaigns.FiltersLiveTest do
  use ColtWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, Company}

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "f@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp log_in(conn, user) do
    {:ok, token, _} = AshAuthentication.Jwt.token_for_user(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("user_token", token)
  end

  defp seed_companies do
    for i <- 1..6 do
      Company.upsert_basic!(%{
        registry_code: "T#{i}",
        market: :ee,
        name: "Co #{i}",
        region: "Tallinn",
        status: :registered
      })
    end

    Company.upsert_basic!(%{
      registry_code: "TXX",
      market: :ee,
      name: "Liquidating",
      region: "Tartu",
      status: :liquidation
    })
  end

  defp setup_campaign(user) do
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)
    {:ok, c} = Campaign.set_icp(c, "B2B", "CTO", :b2b, actor: user)
    {:ok, c} = Campaign.update_filters(c, %{markets: ["ee"]}, actor: user)
    c
  end

  test "renders counter with registered count, excluding liquidation by default", %{conn: conn} do
    seed_companies()
    user = seed_user()
    c = setup_campaign(user)
    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{c.id}/filters")

    # The summary is loaded off the mount path (connected mount only), so read
    # it from the live view after the :reload has been processed.
    html = render(view)
    assert html =~ "Companies match"
    assert html =~ "of 6"
  end

  # seed_user is the first user in an empty table → auto-promoted to admin,
  # so it clears the pricing gate and proceeds into setup.
  test "confirm saves filters and redirects to icp (status stays :collecting)", %{conn: conn} do
    seed_companies()
    user = seed_user()
    c = setup_campaign(user)
    conn = log_in(conn, user)

    {:ok, view, _} = live(conn, ~p"/campaigns/#{c.id}/filters")

    {:error, {:live_redirect, %{to: to}}} = render_click(view, "confirm", %{})

    assert to == "/campaigns/#{c.id}/icp"

    {:ok, fresh} = Campaign.get(c.id, actor: user)
    assert fresh.status == :collecting
    assert is_map(fresh.filters)
  end
end
