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

  test "view 0 — create campaign and advance to ICP", %{conn: conn} do
    user = seed_user()
    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    assert render(view) =~ "What are we calling this"

    {:error, {:live_redirect, %{to: to}}} =
      view
      |> form("form", %{"name" => "Test EE SaaS"})
      |> render_submit()

    assert to =~ ~r"^/campaigns/[^/]+/icp$"
  end

  test "view 0 — empty name shows error, no campaign created", %{conn: conn} do
    user = seed_user()
    conn = log_in(conn, user)

    {:ok, view, _} = live(conn, ~p"/campaigns/new")

    html =
      view
      |> form("form", %{"name" => ""})
      |> render_submit()

    assert html =~ "Name a campaign"
    assert Campaign.list_recent_for_user!(user.id, actor: user) == []
  end

  test "view 1 — save ICP advances to market", %{conn: conn} do
    user = seed_user()
    conn = log_in(conn, user)
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)

    {:ok, view, _} = live(conn, ~p"/campaigns/#{c.id}/icp")

    {:error, {:live_redirect, %{to: to}}} =
      view
      |> form("form", %{
        "icp_description" => "B2B SaaS",
        "target_job_title" => "CTO"
      })
      |> render_submit()

    assert to == "/campaigns/#{c.id}/market"

    {:ok, fresh} = Campaign.get(c.id, actor: user)
    assert fresh.icp_description == "B2B SaaS"
    assert fresh.target_job_title == "CTO"
    assert fresh.status == :draft
  end

  test "view 2 — EE preselected, FI disabled, continue moves to :collecting", %{conn: conn} do
    user = seed_user()
    conn = log_in(conn, user)
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)
    {:ok, c} = Campaign.set_icp(c, "B2B SaaS", "CTO", :b2b, actor: user)

    {:ok, view, html} = live(conn, ~p"/campaigns/#{c.id}/market")

    assert html =~ "Estonia"
    assert html =~ "Finland"
    assert html =~ "soon"
    assert has_element?(view, "button[phx-value-market='fi'][disabled]")

    # Clicking a disabled market is a no-op (still selected = :ee).
    render_click(view, "select", %{"market" => "fi"})

    {:error, {:live_redirect, %{to: to}}} = render_click(view, "continue", %{})

    assert to == "/campaigns/#{c.id}/filters"
    {:ok, fresh} = Campaign.get(c.id, actor: user)
    assert fresh.market == :ee
    assert fresh.status == :collecting
  end

  test "recent sidebar lists user's campaigns with 0/0 ratio", %{conn: conn} do
    user = seed_user()
    conn = log_in(conn, user)
    {:ok, _} = Campaign.create_draft("Test EE SaaS", actor: user)

    {:ok, _view, html} = live(conn, ~p"/campaigns/new")

    assert html =~ "Test EE SaaS"
    assert html =~ "0 / 0"
  end
end
