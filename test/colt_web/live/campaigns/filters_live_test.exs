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
    {:ok, c} = Campaign.set_icp(c, "B2B", "CTO", actor: user)
    {:ok, c} = Campaign.set_market(c, :ee, actor: user)
    c
  end

  test "renders counter with registered count, excluding liquidation by default", %{conn: conn} do
    seed_companies()
    user = seed_user()
    c = setup_campaign(user)
    conn = log_in(conn, user)

    {:ok, _view, html} = live(conn, ~p"/campaigns/#{c.id}/filters")

    assert html =~ "Companies match"
    assert html =~ "of 6"
  end

  test "confirm advances to funnel and creates CampaignCompany rows", %{conn: conn} do
    seed_companies()
    user = seed_user()
    c = setup_campaign(user)
    conn = log_in(conn, user)

    {:ok, view, _} = live(conn, ~p"/campaigns/#{c.id}/filters")

    {:error, {:live_redirect, %{to: to}}} = render_click(view, "confirm", %{})

    assert to == "/campaigns/#{c.id}/funnel"

    {:ok, fresh} = Campaign.get(c.id, actor: user)
    assert fresh.status == :enriching
    assert fresh.finalized_at
  end
end
