defmodule ColtWeb.Components.FunnelThreadTest do
  @moduledoc """
  The timeline renders bodies it did not author, so these cover both halves of
  that: the formatting has to survive to the page, and the markup has to be
  sanitized on the way.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias ColtWeb.Components.FunnelThread

  defp card(item), do: render_component(&FunnelThread.timeline_item/1, item: item)

  defp manual_reply(body) do
    %{
      kind: :manual_outbound,
      at: ~U[2026-08-06 10:27:38.464583Z],
      email: %{
        status: :sent,
        step_position: nil,
        is_manual_reply: true,
        user_body: body,
        ai_body: nil,
        user_subject: "re: ukselingide müük",
        ai_subject: nil
      }
    }
  end

  defp inbound(body) do
    %{
      kind: :inbound,
      at: ~U[2026-08-06 09:00:00Z],
      email: %{body: body, subject: "re: ukselingide müük", from_address: "rene@example.com"}
    }
  end

  test "a link written in the composer reaches the page as a link" do
    body =
      ~s(<div>Ülevaade: <a href="https://liid.ee/demo/features">liid.ee/demo/features</a></div>)

    html = card(manual_reply(body))

    assert html =~ ~s(<a href="https://liid.ee/demo/features">)
    assert html =~ "email-html"
  end

  test "formatting survives instead of being flattened to text" do
    html = card(manual_reply("<div><strong>Tähtis</strong><br>uus rida</div>"))

    assert html =~ "<strong>Tähtis</strong>"
    assert html =~ "<br"
  end

  test "a plain-text AI draft still renders its line breaks" do
    item = %{
      kind: :outbound,
      at: ~U[2026-06-15 13:15:01Z],
      email: %{
        status: :sent,
        step_position: 0,
        is_manual_reply: false,
        user_body: nil,
        ai_body: "Tere Rene\n\nKrister",
        user_subject: nil,
        ai_subject: "ukselingide müük"
      }
    }

    html = card(item)
    assert html =~ "Tere Rene"
    assert html =~ ~r{<br\s*/?>}
  end

  test "an inbound reply cannot inject script into the thread" do
    html = card(inbound(~s|<div>Sobib!<script>alert(1)</script></div>|))

    assert html =~ "Sobib!"
    refute html =~ "<script>"
    refute html =~ "alert(1)"
  end

  test "an inbound reply's quoted history is split into the disclosure" do
    body = """
    <div dir="ltr">Sobib, saada!</div>
    <div class="gmail_quote">
      <div class="gmail_attr">On Mon, Jun 15, 2026 Oscar wrote:</div>
      <blockquote class="gmail_quote">vana pitch</blockquote>
    </div>
    """

    html = card(inbound(body))

    assert html =~ "Sobib, saada!"
    assert html =~ "<details"
    assert html =~ "vana pitch"
  end
end
