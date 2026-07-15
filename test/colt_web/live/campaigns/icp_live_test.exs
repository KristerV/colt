defmodule ColtWeb.Campaigns.IcpLiveTest do
  use ColtWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Colt.Accounts.User
  alias Colt.Resources.Campaign

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "icp@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp log_in(conn, user) do
    {:ok, token, _} = AshAuthentication.Jwt.token_for_user(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("user_token", token)
  end

  defp setup_campaign(user) do
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)
    c
  end

  defp base_params(overrides) do
    Map.merge(
      %{
        "icp_description" => "B2B software firms",
        "target_job_title" => "CTO",
        # Hidden input driven by the button group, not the form — LiveViewTest
        # holds us to the rendered value, which is the campaign's default.
        "business_model" => "both",
        "reach_owner" => "true",
        "reach_title" => "true",
        "reach_generic" => "false",
        "require_website" => "true"
      },
      overrides
    )
  end

  setup %{conn: conn} do
    user = seed_user()
    campaign = setup_campaign(user)
    %{conn: log_in(conn, user), user: user, campaign: campaign}
  end

  test "defaults: owner and title on, generic off, website required", %{campaign: c} do
    assert c.reach_owner?
    assert c.reach_title?
    refute c.reach_generic?
    assert c.require_website?
  end

  test "renders the three rungs in ladder order", %{conn: conn, campaign: c} do
    {:ok, _lv, html} = live(conn, ~p"/campaigns/#{c.id}/icp")

    assert html =~ "Who should we reach?"

    owner_at = :binary.match(html, "Owner") |> elem(0)
    title_at = :binary.match(html, "Job title") |> elem(0)
    generic_at = :binary.match(html, "Generic inbox") |> elem(0)

    assert owner_at < title_at and title_at < generic_at,
           "rungs must render in the fixed ladder order owner -> title -> generic"
  end

  test "saves the rung selection", %{conn: conn, campaign: c, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/campaigns/#{c.id}/icp")

    lv
    |> form("#icp-form", base_params(%{"reach_title" => "false", "reach_generic" => "true"}))
    |> render_submit()

    {:ok, saved} = Campaign.get(c.id, actor: user)
    assert saved.reach_owner?
    refute saved.reach_title?
    assert saved.reach_generic?
  end

  test "an unticked box actually turns the rung off", %{conn: conn, campaign: c, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/campaigns/#{c.id}/icp")

    # A real browser omits an unchecked box entirely; the hidden "false" input is
    # what makes the off state survive. Simulate the omission.
    params =
      base_params(%{})
      |> Map.delete("reach_owner")
      |> Map.put("reach_owner", "false")

    lv |> form("#icp-form", params) |> render_submit()

    {:ok, saved} = Campaign.get(c.id, actor: user)
    refute saved.reach_owner?
  end

  test "refuses to save with every rung off", %{conn: conn, campaign: c, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/campaigns/#{c.id}/icp")

    html =
      lv
      |> form(
        "#icp-form",
        base_params(%{
          "reach_owner" => "false",
          "reach_title" => "false",
          "reach_generic" => "false"
        })
      )
      |> render_submit()

    assert html =~ "Pick at least one way to reach someone"

    {:ok, saved} = Campaign.get(c.id, actor: user)
    assert saved.reach_owner?, "must not have persisted an unreachable campaign"
  end

  test "the title rung requires a title, other rungs don't", %{
    conn: conn,
    campaign: c,
    user: user
  } do
    {:ok, lv, _html} = live(conn, ~p"/campaigns/#{c.id}/icp")

    html =
      lv
      |> form("#icp-form", base_params(%{"target_job_title" => ""}))
      |> render_submit()

    assert html =~ "Add a target job title"

    # Same empty title, but the title rung is off — now it's fine.
    lv
    |> form(
      "#icp-form",
      base_params(%{"target_job_title" => "", "reach_title" => "false"})
    )
    |> render_submit()

    {:ok, saved} = Campaign.get(c.id, actor: user)
    refute saved.reach_title?
  end

  test "unticking the website requirement surfaces the ICP warning", %{conn: conn, campaign: c} do
    {:ok, lv, html} = live(conn, ~p"/campaigns/#{c.id}/icp")
    refute html =~ "targeted on your filters alone"

    html =
      lv |> form("#icp-form", base_params(%{"require_website" => "false"})) |> render_change()

    assert html =~ "targeted on your filters alone",
           "dropping the website requirement disables the ICP check; the user must be told"
  end
end
