defmodule ColtWeb.Admin.ClientsLiveTest do
  use ColtWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignCompany, Company, Person, RevenueEntry}
  alias Colt.Services.Admin.{ClientList, ClientProfile}

  # The first seeded user is auto-promoted to admin (see first_admin_test).
  defp seed_user(email) do
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

  defp seed_campaign(owner, name) do
    Campaign.create_draft!(name, actor: owner)
  end

  defp seed_enriched(campaign) do
    company =
      Company.upsert_basic!(
        %{
          registry_code: "EE-#{System.unique_integer([:positive])}",
          market: :ee,
          name: "Acme OÜ"
        },
        authorize?: false
      )

    CampaignCompany
    |> Ash.Changeset.for_create(
      :create,
      %{campaign_id: campaign.id, company_id: company.id},
      authorize?: false
    )
    |> Ash.create!(authorize?: false)
    |> CampaignCompany.mark_enriched!(authorize?: false)
  end

  # Both pages cache for 24h, so every test has to bust the memo after seeding.
  defp visit_list(conn) do
    ClientList.refresh()
    live(conn, ~p"/admin/clients")
  end

  defp visit_client(conn, user) do
    ClientList.refresh()
    ClientProfile.refresh(user.id)
    live(conn, ~p"/admin/clients/#{user.id}")
  end

  # The clients in table order. Read off the row navigation targets rather than
  # scanning for emails — the sidebar prints the logged-in user's address above
  # the table and would otherwise come first.
  defp rendered_order(html) do
    emails = Map.new(Colt.Accounts.list_users!(authorize?: false), &{&1.id, to_string(&1.email)})

    ~r|/admin/clients/([0-9a-f-]{36})|
    |> Regex.scan(html)
    |> Enum.map(fn [_, id] -> id end)
    |> Enum.uniq()
    |> Enum.map(&Map.fetch!(emails, &1))
  end

  defp current_ym do
    %{year: y, month: m} = DateTime.utc_now()
    "#{y}-#{m |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  setup %{conn: conn} do
    admin = seed_user("admin@example.com")
    %{conn: log_in(conn, admin), admin: admin}
  end

  describe "the list" do
    test "shows every client with its activation funnel", %{conn: conn, admin: admin} do
      campaign = seed_campaign(admin, "koristaja")
      seed_enriched(campaign)

      {:ok, _view, html} = visit_list(conn)

      assert html =~ "All"
      assert html =~ "admin@example.com"
      assert html =~ "campaigns → inboxes → with enriched → with sent → with interested"
    end

    test "is ordered by registration date, newest first, by default", %{conn: conn} do
      seed_user("later@example.com")

      {:ok, _view, html} = visit_list(conn)

      # Compare against the users' own timestamps rather than seeding order, so
      # the test doesn't depend on the clock ticking between two inserts.
      expected =
        Colt.Accounts.list_users!(authorize?: false)
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
        |> Enum.map(&to_string(&1.email))

      assert rendered_order(html) == expected
    end

    test "sorting by a column re-orders the table", %{conn: conn} do
      seed_user("later@example.com")
      {:ok, view, _html} = visit_list(conn)

      html = view |> element("th button[phx-value-by=email]") |> render_click()

      # A→Z on first press.
      assert rendered_order(html) == ["admin@example.com", "later@example.com"]
    end

    test "a row links through to the client view", %{conn: conn, admin: admin} do
      {:ok, _view, html} = visit_list(conn)

      assert html =~ "/admin/clients/#{admin.id}"
    end

    test "non-admins are redirected away", %{conn: conn} do
      seed_user("admin@example.com")
      plain = seed_user("plain@example.com")

      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in(plain) |> live(~p"/admin/clients")
    end
  end

  describe "the client view" do
    test "renders the funnel, money and campaigns", %{conn: conn, admin: admin} do
      campaign = seed_campaign(admin, "koristaja tere")
      seed_enriched(campaign)

      {:ok, _view, html} = visit_client(conn, admin)

      assert html =~ "what to talk about"
      assert html =~ "where they get stuck"
      assert html =~ "companies pulled"
      assert html =~ "koristaja tere"
      assert html =~ "/campaigns/#{campaign.id}/funnel"
    end

    test "the month table reports the funnel per month, not revenue and cost", %{
      conn: conn,
      admin: admin
    } do
      campaign = seed_campaign(admin, "monthly")
      seed_enriched(campaign)

      {:ok, _view, html} = visit_client(conn, admin)

      assert html =~ "month by month"

      for column <- ~w(screened enriched emailed interested profit) do
        assert html =~ column
      end

      # This month's enrichment shows up as a screened + enriched contact.
      assert html =~ current_ym()
    end

    test "the stuck block carries the plan and inbox chips", %{conn: conn, admin: admin} do
      {:ok, _view, html} = visit_client(conn, admin)

      assert html =~ "where they get stuck"
      assert html =~ "registered"
      assert html =~ "inboxes"
      assert html =~ "0 of 0 working"
    end

    test "the funnel chain is only companies, contacts and emails", %{conn: conn, admin: admin} do
      campaign = seed_campaign(admin, "chain")
      seed_enriched(campaign)

      {:ok, _view, html} = visit_client(conn, admin)

      for step <- ["companies pulled", "screened", "enriched", "emailed", "replied", "interested"] do
        assert html =~ step
      end

      # Inboxes are a capability, not a stage — they never join the drop chain.
      refute html =~ "can&#39;t send"
    end

    test "names the stall when a client enriches but never sends", %{conn: conn, admin: admin} do
      campaign = seed_campaign(admin, "stalled")
      seed_enriched(campaign)

      {:ok, _view, html} = visit_client(conn, admin)

      assert html =~ "enriched"
      assert html =~ "nothing sent"
    end

    test "flags a client who never created a campaign", %{conn: conn} do
      seed_user("admin@example.com")
      dormant = seed_user("dormant@example.com")

      {:ok, _view, html} = visit_client(conn, dormant)

      assert html =~ "never created a campaign"
      assert html =~ "they&#39;ve never started"
    end

    test "records and deletes manual revenue", %{conn: conn, admin: admin} do
      {:ok, view, _html} = visit_client(conn, admin)

      # Revenue entry lives behind the month row's button now.
      view |> element(~s{button[phx-value-month="#{current_ym()}"]}) |> render_click()

      html =
        view
        |> form("form[phx-submit=add_revenue]", %{
          "revenue" => %{
            "month" => current_ym(),
            "amount_usd" => "159",
            "source" => "invoice",
            "note" => "test invoice"
          }
        })
        |> render_submit()

      assert html =~ "test invoice"
      assert html =~ "$159.00"

      [entry] = RevenueEntry.list_for_user!(admin.id, authorize?: false)
      html = view |> element(~s{button[phx-value-id="#{entry.id}"]}) |> render_click()

      assert html =~ "no revenue recorded yet"
    end

    test "auto-links the client to a person we already enriched, by email", %{conn: conn} do
      seed_user("admin@example.com")

      company =
        Company.upsert_basic!(
          %{registry_code: "EE-9001", market: :ee, name: "Täp OÜ"},
          authorize?: false
        )

      Person.create_validated!(
        %{company_id: company.id, name: "Krister V", email: "client@tap.ee", phone: "+372 5000"},
        authorize?: false
      )

      client = seed_user("client@tap.ee")

      {:ok, _view, html} = visit_client(conn, client)

      assert html =~ "Täp OÜ"
      assert html =~ "Krister V"
      assert html =~ "+372 5000"
      assert html =~ "auto-matched"

      assert %{person_id: person_id} = Ash.get!(User, client.id, authorize?: false)
      assert person_id
    end

    test "a manual override wins over the linked record", %{conn: conn} do
      seed_user("admin@example.com")

      company =
        Company.upsert_basic!(
          %{registry_code: "EE-9002", market: :ee, name: "Linked OÜ"},
          authorize?: false
        )

      Person.create_validated!(
        %{company_id: company.id, name: "Linked Name", email: "over@tap.ee", phone: "+372 1111"},
        authorize?: false
      )

      client = seed_user("over@tap.ee")
      {:ok, view, _html} = visit_client(conn, client)

      view |> element("button[phx-click=open_identity]") |> render_click()

      html =
        view
        |> form("form[phx-submit=save_profile]", %{"profile" => %{"phone" => "+372 9999"}})
        |> render_submit()

      # Saving closes the modal; the card shows the effective value.
      assert html =~ "Linked Name · +372 9999"
      refute html =~ "Linked Name · +372 1111"

      # Reopening shows the override in the field and the linked value as the
      # placeholder — so clearing it falls back rather than losing the link.
      html = view |> element("button[phx-click=open_identity]") |> render_click()

      assert html =~ ~s{value="+372 9999"}
      assert html =~ ~s{placeholder="+372 1111"}
    end

    test "granting admin promotes the client and hides the button", %{conn: conn} do
      seed_user("admin@example.com")
      client = seed_user("plain@example.com")

      {:ok, view, html} = visit_client(conn, client)
      assert html =~ "Make admin"

      html = view |> element("button[phx-click=grant_admin]") |> render_click()

      assert html =~ "· admin"
      refute html =~ "Make admin"
      assert Ash.get!(User, client.id, authorize?: false).is_admin
    end

    test "an already-admin client shows no make-admin button", %{conn: conn, admin: admin} do
      {:ok, _view, html} = visit_client(conn, admin)

      assert html =~ "· admin"
      refute html =~ "Make admin"
    end

    test "searching links a company by hand", %{conn: conn} do
      seed_user("admin@example.com")
      client = seed_user("nomatch@example.com")

      company =
        Company.upsert_basic!(
          %{registry_code: "EE-9003", market: :ee, name: "Searchable OÜ"},
          authorize?: false
        )

      {:ok, view, _html} = visit_client(conn, client)

      view |> element("button[phx-click=open_identity]") |> render_click()
      view |> element("button[phx-click=open_search]") |> render_click()
      html = view |> form("form[phx-change=search]", %{"q" => "Searchable"}) |> render_change()
      assert html =~ "Searchable OÜ"

      html = view |> element(~s{button[phx-value-company_id="#{company.id}"]}) |> render_click()
      assert html =~ "Searchable OÜ"

      assert %{company_id: linked} = Ash.get!(User, client.id, authorize?: false)
      assert linked == company.id
    end
  end
end
