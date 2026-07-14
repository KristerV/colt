defmodule ColtWeb.Admin.CountriesLiveTest do
  use ColtWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Colt.Accounts.User
  alias Colt.Resources.Company

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

  defp seed_company(market) do
    Company.upsert_basic!(
      %{
        registry_code: "#{market}-1",
        market: market,
        name: "#{market} co",
        status: :registered
      },
      authorize?: false
    )
  end

  # market_stats is memoized 24h, so each test must bust the memo after seeding
  # or it renders the previous test's registry.
  defp visit(conn) do
    Company.refresh_market_stats()
    live(conn, ~p"/admin/countries")
  end

  setup %{conn: conn} do
    user = seed_admin()
    %{conn: log_in(conn, user)}
  end

  test "lists every country declared in config, available or not", %{conn: conn} do
    {:ok, _view, html} = visit(conn)

    for name <- ~w(Estonia Finland Latvia Lithuania Norway Denmark Sweden Poland) do
      assert html =~ name
    end
  end

  test "available markets carrying rows read as available", %{conn: conn} do
    Enum.each(Colt.Markets.available_atoms(), &seed_company/1)
    {:ok, _view, html} = visit(conn)

    assert html =~ "Available"
    refute html =~ "Available · no data"
  end

  test "an available market with no rows is flagged — this is the Denmark bug", %{conn: conn} do
    {:ok, _view, html} = visit(conn)

    assert html =~ "Available · no data"
  end

  test "an unavailable market carrying rows is flagged", %{conn: conn} do
    seed_company(:dk)
    {:ok, _view, html} = visit(conn)

    assert html =~ "Has data · not offered"
  end

  test "counts render for markets with rows and dashes for those without", %{conn: conn} do
    seed_company(:ee)
    {:ok, _view, html} = visit(conn)

    assert html =~ "—"
  end
end
