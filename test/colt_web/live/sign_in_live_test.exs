defmodule ColtWeb.SignInLiveTest do
  use ColtWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "sign-in page tells visitors how to get an account", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/sign-in")
    assert html =~ "liid@krister.ee"
    assert html =~ "invite-only"
  end

  test "/register is gone", %{conn: conn} do
    assert get(conn, "/register").status == 404
  end
end
