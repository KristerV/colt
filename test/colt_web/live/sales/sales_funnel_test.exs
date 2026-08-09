defmodule ColtWeb.Sales.SalesFunnelTest do
  @moduledoc """
  Wiring smoke test for the sales funnel board and the checklist page.

  The bucket maths is covered in `Colt.Resources.CampaignContactSalesBucketTest`; what's tested
  here is everything that only breaks at runtime — the routes, the admin gate,
  the derived bucket tiles actually filtering, and the three controls that
  move a contact (`Next action`, `Won`/`Lost`, checklist ticks) reaching their
  services with the right arguments.
  """
  use ColtWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignContact}
  alias Colt.SalesClock
  alias Colt.Services.Sales.{CreateManualContact, SeedChecklist, SetNextAction}

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

  defp sales_contact(campaign, user, name) do
    {:ok, contact} =
      CreateManualContact.run(
        campaign.id,
        %{
          name: name,
          company_name: "Kohvik OÜ",
          registry_code: "1#{System.unique_integer([:positive])}",
          market: :ee,
          in_funnel_sales?: true,
          in_funnel_sending?: false
        },
        actor: user
      )

    contact
  end

  defp reload(contact_id) do
    Ash.get!(CampaignContact, contact_id, load: [:sales_bucket], authorize?: false)
  end

  setup %{conn: conn} do
    user = seed_admin()
    {:ok, campaign} = Campaign.create_draft("Hunt", actor: user)
    %{conn: log_in(conn, user), user: user, campaign: campaign}
  end

  describe "the board" do
    test "shows the four derived buckets with live counts", %{
      conn: conn,
      user: user,
      campaign: campaign
    } do
      sales_contact(campaign, user, "Untriaged Jane")
      later = sales_contact(campaign, user, "Scheduled Jaan")
      {:ok, _} = SetNextAction.run(later.id, SalesClock.in_days(5), actor: user)

      {:ok, _view, html} = live(conn, ~p"/campaigns/#{campaign.id}/sales")

      assert html =~ "Now"
      assert html =~ "Later"
      assert html =~ "Won"
      assert html =~ "Lost"
    end

    test "the Now bucket lists undated contacts and Later does not", %{
      conn: conn,
      user: user,
      campaign: campaign
    } do
      sales_contact(campaign, user, "Untriaged Jane")

      {:ok, _view, now_html} = live(conn, ~p"/campaigns/#{campaign.id}/sales/now")
      assert now_html =~ "Untriaged Jane"
      assert now_html =~ "No date"

      {:ok, _view, later_html} = live(conn, ~p"/campaigns/#{campaign.id}/sales/later")
      refute later_html =~ "Untriaged Jane"
    end

    test "a contact dated today stays in Now, not Later", %{
      conn: conn,
      user: user,
      campaign: campaign
    } do
      contact = sales_contact(campaign, user, "Due Today Jane")
      {:ok, _} = SetNextAction.run(contact.id, SalesClock.in_days(0), actor: user)

      {:ok, _view, now_html} = live(conn, ~p"/campaigns/#{campaign.id}/sales/now")
      assert now_html =~ "Due Today Jane"
      assert now_html =~ "Today"

      {:ok, _view, later_html} = live(conn, ~p"/campaigns/#{campaign.id}/sales/later")
      refute later_html =~ "Due Today Jane"
    end

    test "an overdue contact is flagged", %{conn: conn, user: user, campaign: campaign} do
      contact = sales_contact(campaign, user, "Late Jane")
      {:ok, _} = SetNextAction.run(contact.id, SalesClock.in_days(-4), actor: user)

      {:ok, _view, html} = live(conn, ~p"/campaigns/#{campaign.id}/sales/now")

      assert html =~ "4d overdue"
    end
  end

  describe "controls" do
    test "Next action moves the contact to Later", %{
      conn: conn,
      user: user,
      campaign: campaign
    } do
      contact = sales_contact(campaign, user, "Jane Tamm")

      {:ok, view, _html} =
        live(conn, ~p"/campaigns/#{campaign.id}/sales/now/#{contact.id}")

      view |> element("button", "In 3 days") |> render_click()

      assert reload(contact.id).sales_bucket == :later
    end

    test "Won closes the contact and Reopen brings it back to Now", %{
      conn: conn,
      user: user,
      campaign: campaign
    } do
      contact = sales_contact(campaign, user, "Jane Tamm")

      {:ok, view, _html} =
        live(conn, ~p"/campaigns/#{campaign.id}/sales/now/#{contact.id}")

      view |> element("button", "Won") |> render_click()
      assert reload(contact.id).sales_bucket == :won

      {:ok, view, _html} =
        live(conn, ~p"/campaigns/#{campaign.id}/sales/won/#{contact.id}")

      view |> element("button", "Reopen") |> render_click()
      assert reload(contact.id).sales_bucket == :now
    end

    test "Lost asks for a reason before closing", %{
      conn: conn,
      user: user,
      campaign: campaign
    } do
      contact = sales_contact(campaign, user, "Jane Tamm")

      {:ok, view, _html} =
        live(conn, ~p"/campaigns/#{campaign.id}/sales/now/#{contact.id}")

      html = view |> element("button", "Lost") |> render_click()

      # Still open — the modal is what appeared, not the outcome.
      assert html =~ "Why was this lost?"
      assert reload(contact.id).outcome == nil

      render_change(view, "set_lost_reason", %{"value" => "went with a competitor"})
      view |> element("button", "Mark lost") |> render_click()

      reloaded = reload(contact.id)
      assert reloaded.sales_bucket == :lost
      assert reloaded.outcome_reason == "went with a competitor"
    end

    test "the thread shows the campaign checklist and ticks persist", %{
      conn: conn,
      user: user,
      campaign: campaign
    } do
      {:ok, [first | _]} = SeedChecklist.run(campaign.id, actor: user)
      contact = sales_contact(campaign, user, "Jane Tamm")

      {:ok, view, html} =
        live(conn, ~p"/campaigns/#{campaign.id}/sales/now/#{contact.id}")

      # The bar surfaces the next unticked item plus progress. ("Checklist" on
      # its own would pass off the sidebar nav item, so assert on the content.)
      assert html =~ "Intro call"
      assert html =~ "0/3"

      html = render_click(view, "toggle_checklist", %{"item" => first.id})
      assert html =~ "1/3"

      # Ticking the first item advances what the bar advertises as next.
      assert html =~ "Demo booked"

      # Ticking is not a bucket move — the contact stays where it was.
      assert reload(contact.id).sales_bucket == :now
    end

    test "the bar carries the contact info and Edit inside the name disclosure", %{
      conn: conn,
      user: user,
      campaign: campaign
    } do
      contact = sales_contact(campaign, user, "Jane Tamm")

      {:ok, _view, html} =
        live(conn, ~p"/campaigns/#{campaign.id}/sales/now/#{contact.id}")

      # The panel is rendered but hidden — the disclosure is CSS, not a
      # round-trip, so the details must be in the markup.
      assert html =~ "Jane Tamm"
      assert html =~ "Kohvik OÜ"
      assert html =~ "Edit"
      assert html =~ ~s(id="contact-info-#{contact.id}")
    end

    test "the timeline scroller is keyed on the contact so it re-pins per thread", %{
      conn: conn,
      user: user,
      campaign: campaign
    } do
      contact = sales_contact(campaign, user, "Jane Tamm")

      {:ok, _view, html} =
        live(conn, ~p"/campaigns/#{campaign.id}/sales/now/#{contact.id}")

      # Keying matters: with a static id the hook never remounts, so switching
      # contacts would inherit the previous thread's scroll offset.
      assert html =~ ~s(phx-hook="ThreadScroll")
      assert html =~ ~s(id="thread-scroll-#{contact.id}")
    end

    test "a checklist tick logs as a checkbox, not as an arrow transition", %{
      conn: conn,
      user: user,
      campaign: campaign
    } do
      {:ok, [first | _]} = SeedChecklist.run(campaign.id, actor: user)
      contact = sales_contact(campaign, user, "Jane Tamm")

      {:ok, view, _html} =
        live(conn, ~p"/campaigns/#{campaign.id}/sales/now/#{contact.id}")

      html = render_click(view, "toggle_checklist", %{"item" => first.id})

      # The item name appears in the feed, but never as "→ Intro call", and the
      # raw marker word is not printed as a second line.
      assert html =~ "Intro call"
      refute html =~ "→ Intro call"
      refute html =~ "unchecked"

      # Entry reads as a sentence rather than a move into a stale stage name.
      assert html =~ "Entered the sales funnel"
      refute html =~ "entered sales funnel"
    end
  end

  describe "checklist page" do
    test "offers the starter checklist when empty, then lists the items", %{
      conn: conn,
      campaign: campaign
    } do
      {:ok, view, html} = live(conn, ~p"/campaigns/#{campaign.id}/sales/checklist")

      assert html =~ "No checklist yet."

      html = view |> element("button", "Use starter checklist") |> render_click()

      assert html =~ "Intro call"
      assert html =~ "Demo booked"
      assert html =~ "Proposal sent"
    end
  end

  describe "admin gate" do
    test "a non-admin cannot reach the board", %{conn: conn} do
      other =
        User
        |> Ash.Changeset.for_create(:seed, %{email: "regular@example.com"}, authorize?: false)
        |> Ash.create!(authorize?: false)

      refute other.is_admin

      {:ok, campaign} = Campaign.create_draft("Theirs", actor: other)

      assert {:error, {:redirect, %{to: "/"}}} =
               conn
               |> log_in(other)
               |> live(~p"/campaigns/#{campaign.id}/sales")
    end
  end
end
