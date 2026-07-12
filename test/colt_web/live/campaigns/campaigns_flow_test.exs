defmodule ColtWeb.Campaigns.FlowTest do
  use ColtWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Colt.Accounts.User
  alias Colt.Resources.Campaign

  defp seed_user(email \\ "user@example.com") do
    User
    |> Ash.Changeset.for_create(:seed, %{email: email}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp log_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("user_token", token)
  end

  test "view 0 — create campaign and advance to filters", %{conn: conn} do
    user = seed_user()
    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    assert render(view) =~ "What are we calling this"

    {:error, {:live_redirect, %{to: to}}} =
      view
      |> form("#campaign-new-form", %{"name" => "Test EE SaaS"})
      |> render_submit()

    assert to =~ ~r"^/campaigns/[^/]+/filters$"
  end

  test "view 0 — empty name shows error, no campaign created", %{conn: conn} do
    user = seed_user()
    conn = log_in(conn, user)

    {:ok, view, _} = live(conn, ~p"/campaigns/new")

    html =
      view
      |> form("#campaign-new-form", %{"name" => ""})
      |> render_submit()

    assert html =~ "Name a campaign"
    assert Campaign.list_recent_for_user!(user.id, actor: user) == []
  end

  test "view 1 — save ICP advances to suppression", %{conn: conn} do
    user = seed_user()
    conn = log_in(conn, user)
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)

    {:ok, view, _} = live(conn, ~p"/campaigns/#{c.id}/icp")

    {:error, {:live_redirect, %{to: to}}} =
      view
      |> form("form[phx-submit='save']", %{
        "icp_description" => "B2B SaaS",
        "target_job_title" => "CTO"
      })
      |> render_submit()

    assert to == "/campaigns/#{c.id}/suppression"

    {:ok, fresh} = Campaign.get(c.id, actor: user)
    assert fresh.icp_description == "B2B SaaS"
    assert fresh.target_job_title == "CTO"
    assert fresh.status == :draft
  end

  test "filters — multi-market select, confirm advances to :collecting and ICP", %{conn: conn} do
    user = seed_user()
    conn = log_in(conn, user)
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)
    {:ok, c} = Campaign.set_icp(c, "B2B SaaS", "CTO", :b2b, actor: user)

    {:ok, view, html} = live(conn, ~p"/campaigns/#{c.id}/filters")

    # Enabled markets are offered; disabled ones (SE) are not.
    assert html =~ "Estonia"
    assert html =~ "Latvia"
    refute html =~ "Sweden"

    render_click(view, "toggle", %{"field" => "markets", "v" => "ee"})
    render_click(view, "toggle", %{"field" => "markets", "v" => "lv"})

    {:error, {:live_redirect, %{to: to}}} = render_click(view, "confirm", %{})

    # Seeded user is auto-admin/paid, so confirm goes on to ICP, not pricing.
    assert to == "/campaigns/#{c.id}/icp"

    {:ok, fresh} = Campaign.get(c.id, actor: user)
    assert Enum.sort(fresh.filters["markets"]) == ["ee", "lv"]
    assert fresh.status == :collecting
    assert Campaign.selected_markets(fresh) |> Enum.sort() == [:ee, :lv]
  end
end
