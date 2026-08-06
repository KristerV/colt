defmodule ColtWeb.Admin.AbFunnelTest do
  @moduledoc """
  A smoke test for `/admin/ab`.

  The dashboard is the library's LiveView, so nothing here checks its statistics
  — that is `ab_funnel`'s own suite. What is genuinely ours is the wiring: the
  route, the admin gate, and `Colt.ABTests` being a declaration the library can
  normalise. Every one of those breaks silently at runtime rather than at compile
  time, and the page is behind admin auth where nobody would notice for weeks.
  """
  use ColtWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Colt.Accounts.User

  # The first seeded user is auto-promoted to admin (see first_admin_test).
  defp seed_admin do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "admin@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp log_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("user_token", token)
  end

  defp track(visitor, events, variant) do
    for event <- events do
      AbFunnel.Services.Events.track(visitor, event, %{Colt.ABTests.key() => variant})
    end
  end

  setup %{conn: conn} do
    %{conn: log_in(conn, seed_admin())}
  end

  test "renders the declared deck funnel, including steps nobody reached", %{conn: conn} do
    track("watcher", ~w(deck_started slide_f_intro slide_f_part_contacts), "features")

    {:ok, _view, html} = live(conn, ~p"/admin/ab")

    assert html =~ "Demo deck"
    assert html =~ "Features — the product tour"

    # A slide two steps past where the only visitor stopped. Inferred ordering
    # dropped these entirely, which is the whole reason `steps/1` is declared.
    assert html =~ "Slide f validate"
  end

  test "excludes people who never fired the entry event", %{conn: conn} do
    track("watcher", ~w(deck_started slide_f_intro), "features")
    # Signed in on the landing page, never opened /demo. Counted before the entry
    # gate existed, which is how a step below the entry point ended up holding
    # more people than the entry point itself.
    track("drive-by", ~w(signed_in), "features")

    {:ok, view, _html} = live(conn, ~p"/admin/ab")

    {:ok, report} = AbFunnel.report()
    assert %{exposed: 1} = hd(report.experiments)

    refute render(view) =~ "200"
  end
end
