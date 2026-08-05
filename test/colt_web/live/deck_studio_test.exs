defmodule ColtWeb.DeckStudioTest do
  @moduledoc """
  Smoke coverage for the demo-deck surfaces.

  The studio's state is "does this slide have a clip", the player's is "which
  slides does this variant play, and does it hold on the cover", and the closing
  slide's is "does a choice become a DemoLead" — all easy to break invisibly
  while moving markup around, and none exercised by anything else.
  """
  use ColtWeb.ConnCase, async: false

  import Ecto.Query, only: [where: 3]
  import Phoenix.LiveViewTest

  alias Colt.Accounts.User
  alias Colt.Deck.Manifest
  alias Colt.Resources.DemoLead

  # The manifest is a file in priv/, which the test run shares with the dev
  # machine it is checked out on. Anything a test records has to be handed back
  # exactly as it was found, or running the suite wipes real recordings.
  defp isolate_manifest do
    before = File.read(Manifest.path())

    on_exit(fn ->
      case before do
        {:ok, body} -> File.write!(Manifest.path(), body)
        {:error, _} -> File.rm(Manifest.path())
      end
    end)
  end

  defp admin do
    # First user in an empty table is auto-promoted to admin.
    User
    |> Ash.Changeset.for_create(:seed, %{email: "deck-admin@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp log_in(conn, user) do
    {:ok, token, _} = AshAuthentication.Jwt.token_for_user(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("user_token", token)
  end

  describe "studio" do
    setup %{conn: conn} do
      isolate_manifest()
      File.write!(Manifest.path(), ~s({"slides":{}}\n))

      user = admin()
      assert user.is_admin
      %{conn: log_in(conn, user)}
    end

    test "offers the record button on a slide with no clip", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/deck/f_intro")

      assert html =~ "Record this slide"
      refute html =~ "Delete"

      # Nothing recorded yet, so the bubble is the live camera.
      refute html =~ ~s(id="studio-take")
    end

    test "shows the slide's script as a teleprompter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/deck/f_filter")

      assert html =~ "Script"
      assert html =~ "tegevusala, töötajate arv ja"
    end

    test "shows the clip and a delete button once one exists", %{conn: conn} do
      Manifest.put("f_intro", %{
        media_url: "/media/deck/f_intro-1.mp4",
        media_content_type: "video/mp4",
        duration_ms: 4200,
        recorded_at: DateTime.utc_now()
      })

      {:ok, view, html} = live(conn, ~p"/admin/deck/f_intro")

      assert html =~ "4.2s"
      assert html =~ "Delete"
      refute html =~ "Record this slide"

      # The bubble shows the take, not the live camera, once there is one.
      assert html =~ ~s(id="studio-take")
      assert html =~ "/media/deck/f_intro-1.mp4"

      # Deleting takes two clicks: the first only arms the button.
      armed = view |> element("button[phx-click=delete]") |> render_click()
      assert armed =~ "Click again to delete"
      assert Map.has_key?(Manifest.read(), "f_intro")

      # ...and the second hands the slide back to the recorder, and takes the
      # entry out of the file that prod plays from.
      assert view |> element("button[phx-click=delete]") |> render_click() =~ "Record this slide"
      assert Manifest.read() == %{}
    end

    test "the leads list shows what a viewer chose", %{conn: conn} do
      {:ok, _lead} =
        DemoLead.submit(:call_request, %{
          name: "Jaan",
          phone: "5551234",
          variant: "features",
          visitor_id: "visitor-1",
          slide: "cta"
        })

      {:ok, _view, html} = live(conn, ~p"/admin/demo-leads")

      assert html =~ "Jaan"
      assert html =~ "5551234"
      assert html =~ "wants a call"
    end

    test "totals the recorded runtime for the selected deck", %{conn: conn} do
      # Two clips, one of them on the slide both decks share.
      Manifest.put("f_intro", %{
        media_url: "/media/deck/f_intro-1.mp4",
        media_content_type: "video/mp4",
        duration_ms: 42_000,
        recorded_at: DateTime.utc_now()
      })

      Manifest.put("cta", %{
        media_url: "/media/deck/cta-1.mp4",
        media_content_type: "video/mp4",
        duration_ms: 18_500,
        recorded_at: DateTime.utc_now()
      })

      {:ok, view, html} = live(conn, ~p"/admin/deck")

      # 42s + 18.5s, and 2 of the features deck's 15 slides are in the can.
      assert html =~ "1:00"
      assert html =~ "2 / 15 recorded"

      # The other deck shares only `cta`, so its runtime is that clip alone.
      other =
        view
        |> element("form[phx-change=select_deck]")
        |> render_change(%{"deck" => "solving_emails"})

      assert other =~ "0:18"
      assert other =~ "1 / 9 recorded"
    end

    # Refreshing on a deep link used to land on the first slide of the default
    # deck: mount starts on `features`, and a key that isn't in it fell through
    # to the fallback rather than switching decks.
    test "a link to another deck's slide opens that slide, in that deck", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/deck/s_targeting")

      # The teleprompter is showing that slide's script...
      assert html =~ "Liid käib ka kodukalt kontakte otsimas"

      # ...and the slide list is that slide's deck, not the default one.
      assert html =~ "Risk on su domeen"
      refute html =~ "Kust sa täna kontakte saad"
    end

    test "the deck selector filters the slide list", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/deck")

      assert html =~ "Kust sa täna kontakte saad"

      other =
        view
        |> element("form[phx-change=select_deck]")
        |> render_change(%{"deck" => "solving_emails"})

      refute other =~ "Kust sa täna kontakte saad"
      assert other =~ "Risk on su domeen"
    end
  end

  describe "slides" do
    # Adding a slide means touching four clauses in three places (see
    # docs/demo-deck.md §2). Missing one only shows up when a viewer reaches
    # that slide, which is exactly when you can't fix it.
    test "every key renders, and has a title and a script" do
      for key <- ColtWeb.Deck.Slides.all_keys() do
        assert render_component(&ColtWeb.Deck.Slides.slide/1,
                 key: key,
                 registry_total: 512_000,
                 countries: [],
                 slide_count: 10,
                 minutes: 4
               ) != ""

        assert is_binary(ColtWeb.Deck.Slides.title(key))
        assert is_binary(ColtWeb.Deck.Slides.script(key))
      end
    end

    test "every variant starts on a cover and ends on the shared close" do
      for variant <- ColtWeb.Deck.Slides.variants() do
        keys = ColtWeb.Deck.Slides.order(variant)

        assert ColtWeb.Deck.Slides.cover?(hd(keys))
        assert List.last(keys) == :cta
      end
    end
  end

  describe "player" do
    test "a pinned variant plays that variant's slides", %{conn: conn} do
      {:ok, features_view, features} = live(conn, ~p"/demo/features")
      {:ok, emails_view, emails} = live(conn, ~p"/demo/solving_emails")

      # The cover advertises the length before you press play, and the cover
      # itself isn't counted — it's the Play button, not a slide to sit through.
      assert features =~ "14 slaidi"
      assert emails =~ "8 slaidi"

      # Controls only appear once it's running, and count the pinned variant.
      assert features_view |> element("button[data-deck-start]") |> render_click() =~ "1 / 14"
      assert emails_view |> element("button[data-deck-start]") |> render_click() =~ "1 / 8"
    end

    # A pinned link is how a specific prospect gets sent to a specific cut, and
    # that journey has to show up under the cut they were sent to. AbFunnel
    # tracks from `ab_funnel_variant`, which the cookie owns — so without the
    # override in mount, half of this traffic files features slides under
    # solving_emails and corrupts the funnel rather than just missing from it.
    test "a pinned deck logs its events under the pinned variant", %{conn: conn} do
      view =
        conn
        |> Plug.Test.put_req_cookie("ab_funnel_variant", "solving_emails")
        |> Plug.Test.put_req_cookie("ab_funnel_visitor_id", "visitor-pinned")
        |> then(fn conn -> live(conn, ~p"/demo/features") |> elem(1) end)

      view |> element("button[data-deck-start]") |> render_click()

      variants =
        AbFunnel.Resources.Event
        |> where([e], e.visitor_id == "visitor-pinned" and like(e.event, "slide_%"))
        |> Colt.Repo.all()
        |> Enum.map(& &1.variant)
        |> Enum.uniq()

      assert variants == ["features"]
    end

    test "holds on the cover until Play, then advances off it", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/demo/features")

      # The cover is a slide, not an overlay: its own copy renders, and the
      # deck controls are absent until it's been clicked.
      assert html =~ "Külmaks müügiks"
      refute html =~ ~s(phx-click="toggle_pause")

      after_play = view |> element("button[data-deck-start]") |> render_click()

      assert after_play =~ ~s(phx-click="toggle_pause")
      assert after_play =~ "Kaks asja"
    end

    test "the closing slide's call request records a lead", %{conn: conn} do
      view = play_to_end(conn, ~p"/demo/features")

      assert render(view) =~ "Mis edasi"

      # Choosing opens the panel; the panel is what collects the details.
      assert view
             |> element(~s(button[phx-value-kind="call_request"]))
             |> render_click() =~ "Jäta nimi ja number"

      # A call request without a number is the one thing worth rejecting.
      assert view |> form("form[phx-submit=submit_lead]", %{"name" => "Mari"}) |> render_submit() =~
               "Palun jäta telefoninumber"

      assert DemoLead.list!(authorize?: false) == []

      view
      |> form("form[phx-submit=submit_lead]", %{"name" => "Mari", "phone" => "5551234"})
      |> render_submit()

      assert [lead] = DemoLead.list!(authorize?: false)
      assert lead.kind == :call_request
      assert lead.name == "Mari"
      assert lead.phone == "5551234"
      assert lead.variant == "features"
      assert lead.slide == "cta"
    end

    # The panel closes on success, so the second click of a double-click arrives
    # with nothing being asked. That used to take the LiveView down *after* the
    # lead had been written and Discord pinged.
    test "a second submit after the panel closed is ignored", %{conn: conn} do
      view = play_to_end(conn, ~p"/demo/features")
      view |> element(~s(button[phx-value-kind="call_request"])) |> render_click()

      view
      |> form("form[phx-submit=submit_lead]", %{"name" => "Mari", "phone" => "5551234"})
      |> render_submit()

      assert render_hook(view, "submit_lead", %{"name" => "Mari", "phone" => "5551234"})
      assert [_one] = DemoLead.list!(authorize?: false)
    end

    # `goto` is reachable from any client, and String.to_integer/1 on junk would
    # kill the whole LiveView.
    test "a non-numeric goto index does not crash the player", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/demo/features")
      view |> element("button[data-deck-start]") |> render_click()

      assert render_hook(view, "goto", %{"index" => "not-a-number"})
      assert render(view) =~ "1 / 14"
    end

    test "the try-it choice records a lead and sends them to register", %{conn: conn} do
      view = play_to_end(conn, ~p"/demo/solving_emails")

      assert {:error, {:live_redirect, %{to: "/register"}}} =
               view |> element(~s(button[phx-value-kind="try_it"])) |> render_click()

      assert [lead] = DemoLead.list!(authorize?: false)
      assert lead.kind == :try_it
      assert lead.variant == "solving_emails"
    end

    # Nothing is recorded in test, so every slide falls back to the dwell timer
    # and "advance" is the only way through. Stepping is what the player does on
    # `ended`, so this is the same path a real viewer takes.
    defp play_to_end(conn, path) do
      {:ok, view, _html} = live(conn, path)
      view |> element("button[data-deck-start]") |> render_click()

      Enum.each(1..20, fn _ -> render_hook(view, "advance", %{}) end)

      view
    end
  end
end
