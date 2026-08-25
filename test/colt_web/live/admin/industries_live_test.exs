defmodule ColtWeb.Admin.IndustriesLiveTest do
  use ColtWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Colt.Accounts.User
  alias Colt.Resources.{AnnualReport, Company}
  alias Colt.Services.Admin.IndustryGrowth

  @programming "6210"

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

  defp seed(code, n, base, latest, opts \\ []) do
    {base_year, latest_year} = IndustryGrowth.year_pair()
    market = Keyword.get(opts, :market, :ee)

    for _ <- 1..n do
      company =
        Company.upsert_full!(
          %{
            registry_code: "c#{System.unique_integer([:positive])}",
            market: market,
            name: "co",
            status: :registered,
            industry_code: code
          },
          authorize?: false
        )

      for {year, revenue} <- [{base_year, base}, {latest_year, latest}], revenue do
        AnnualReport.upsert!(
          %{company_id: company.id, year: year, revenue_eur: revenue, source: :rik},
          authorize?: false
        )
      end
    end
  end

  setup %{conn: conn} do
    %{conn: log_in(conn, seed_admin())}
  end

  test "renders every section of the tree, collapsed", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/industries")

    for {_letter, title} <- Colt.Filters.IndustryLabels.sections() do
      assert html =~ title
    end

    # Divisions stay hidden until their section is expanded.
    refute html =~ "Computer programming activities"
  end

  test "shows growth as a percentage and a multiple", %{conn: conn} do
    seed(@programming, 10, 1_000_000, 3_000_000)

    {:ok, _view, html} = live(conn, ~p"/admin/industries")

    assert html =~ "+200%"
    assert html =~ "3.0×"
  end

  test "expanding a section walks down to the class", %{conn: conn} do
    seed(@programming, 10, 1_000_000, 3_000_000)

    {:ok, view, _html} = live(conn, ~p"/admin/industries")

    html =
      view
      |> element("button[phx-value-node='K']")
      |> render_click()

    assert html =~ "Computer programming"

    html = view |> element("button[phx-value-node='62']") |> render_click()
    html = view |> element("button[phx-value-node='621']") |> render_click()

    assert html =~ @programming
  end

  test "collapse all closes what was opened", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/industries")

    view |> element("button[phx-value-node='K']") |> render_click()
    html = view |> element("button[phx-click='collapse_all']") |> render_click()

    refute html =~ "Computer programming activities"
  end

  test "thin industries show their count but no growth figure", %{conn: conn} do
    seed(@programming, 3, 1_000_000, 30_000_000)

    {:ok, view, _html} = live(conn, ~p"/admin/industries")

    html = view |> element("button[phx-value-node='K']") |> render_click()

    # 30x would be the headline if three companies were enough to rank.
    refute html =~ "30.0×"
  end

  test "switching country reloads against that market's filings", %{conn: conn} do
    seed(@programming, 10, 1_000_000, 2_000_000)
    seed(@programming, 10, 1_000_000, 5_000_000, market: :fi)

    {:ok, view, html} = live(conn, ~p"/admin/industries")
    assert html =~ "+100%"

    html = view |> form("form[phx-change='market']", %{"market" => "fi"}) |> render_change()

    assert html =~ "+400%"
  end

  test "says so when the compared years have nothing to compare", %{conn: conn} do
    {_base_year, latest_year} = IndustryGrowth.year_pair()

    {:ok, _view, html} = live(conn, ~p"/admin/industries")

    assert html =~ "No #{latest_year} filings to compare"
  end

  test "is admin-only", %{conn: conn} do
    user =
      User
      |> Ash.Changeset.for_create(:seed, %{email: "member@example.com"}, authorize?: false)
      |> Ash.create!(authorize?: false)

    conn = log_in(Phoenix.ConnTest.build_conn(), user)

    assert {:error, {:redirect, _}} = live(conn, ~p"/admin/industries")
  end
end
