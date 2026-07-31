defmodule ColtWeb.DeckStudioTest do
  @moduledoc """
  Smoke coverage for the demo-deck surfaces.

  The studio's state is "does this slide have a clip" and the player's is "which
  slides does this variant play" — both easy to break invisibly while moving
  markup around, and neither is exercised by anything else.
  """
  use ColtWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Colt.Accounts.User
  alias Colt.Deck.Manifest

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
      {:ok, _view, html} = live(conn, ~p"/admin/deck/hook")

      assert html =~ "Record this slide"
      refute html =~ "Delete"
    end

    test "shows the clip and a delete button once one exists", %{conn: conn} do
      Manifest.put("hook", %{
        media_url: "/media/deck/hook-1.mp4",
        media_content_type: "video/mp4",
        duration_ms: 4200,
        recorded_at: DateTime.utc_now()
      })

      {:ok, view, html} = live(conn, ~p"/admin/deck/hook")

      assert html =~ "4.2s"
      assert html =~ "Delete"
      refute html =~ "Record this slide"

      # Deleting takes two clicks: the first only arms the button.
      armed = view |> element("button[phx-click=delete]") |> render_click()
      assert armed =~ "Click again to delete"
      assert Map.has_key?(Manifest.read(), "hook")

      # ...and the second hands the slide back to the recorder, and takes the
      # entry out of the file that prod plays from.
      assert view |> element("button[phx-click=delete]") |> render_click() =~ "Record this slide"
      assert Manifest.read() == %{}
    end

    test "the deck selector filters the slide list", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/deck")

      assert html =~ "Replies land sorted"

      short =
        view |> element("form[phx-change=select_deck]") |> render_change(%{"deck" => "short"})

      refute short =~ "Replies land sorted"
      assert short =~ "The rest of it, and pricing"
    end
  end

  describe "player" do
    test "a pinned variant plays that variant's slides", %{conn: conn} do
      {:ok, long_view, long} = live(conn, ~p"/demo/long")
      {:ok, short_view, short} = live(conn, ~p"/demo/short")

      # The cover advertises the length before you press play.
      assert long =~ "6 slides"
      assert short =~ "4 slides"

      # Controls only appear once it's running, and count the pinned variant.
      assert long_view |> element("#deck-start") |> render_click() =~ "1 / 6"
      assert short_view |> element("#deck-start") |> render_click() =~ "1 / 4"
    end
  end
end
