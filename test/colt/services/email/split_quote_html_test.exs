defmodule Colt.Services.Email.SplitQuoteHtmlTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Email.SplitQuoteHtml

  test "splits Gmail's quote container" do
    html = """
    <div dir="ltr">Sobib!</div>
    <div class="gmail_quote">
      <div class="gmail_attr">On Mon, Jun 15, 2026 Oscar wrote:</div>
      <blockquote class="gmail_quote">pitch</blockquote>
    </div>
    """

    assert {:ok, %{body: body, quoted: quoted}} = SplitQuoteHtml.run(html)
    assert body =~ "Sobib!"
    refute body =~ "pitch"
    assert quoted =~ "pitch"
  end

  test "splits a bare blockquote" do
    assert {:ok, %{body: body, quoted: quoted}} =
             SplitQuoteHtml.run("<p>Jah</p><blockquote>vana</blockquote>")

    assert body == "<p>Jah</p>"
    assert quoted =~ "vana"
  end

  test "splits Outlook's reply block one level inside the wrapper" do
    html = """
    <div style="color:#000">
      <p>Saada video.</p>
      <div id="appendonsend"></div>
      <hr>
      <div id="divRplyFwdMsg">From: oscar@liids.ee<br>Sent: Monday</div>
    </div>
    """

    assert {:ok, %{body: body, quoted: quoted}} = SplitQuoteHtml.run(html)
    assert body =~ "Saada video."
    refute body =~ "oscar@liids.ee"
    assert quoted =~ "oscar@liids.ee"
    # The wrapper's styling survives on both halves.
    assert body =~ "color:#000"
    assert quoted =~ "color:#000"
  end

  test "splits an Estonian attribution line with no structural marker" do
    html = "<div>Sobib!</div><div>Krister Viirsaar kirjutas:</div><div>vana jutt</div>"

    assert {:ok, %{body: body, quoted: quoted}} = SplitQuoteHtml.run(html)
    assert body == "<div>Sobib!</div>"
    assert quoted =~ "kirjutas:"
    assert quoted =~ "vana jutt"
  end

  test "leaves a message with no quote whole" do
    html = ~s(<div>Hei, ülevaade: <a href="https://liid.ee/demo">siin</a><br>Krister</div>)

    assert {:ok, %{body: ^html, quoted: nil}} = SplitQuoteHtml.run(html)
  end

  test "leaves a message that is entirely quote whole" do
    html = "<blockquote>ainult vana</blockquote>"

    assert {:ok, %{body: ^html, quoted: nil}} = SplitQuoteHtml.run(html)
  end

  test "an image-only body is not treated as empty" do
    html = ~s(<div><img src="https://liid.ee/x.png"></div><blockquote>vana</blockquote>)

    assert {:ok, %{body: body, quoted: quoted}} = SplitQuoteHtml.run(html)
    assert body =~ "x.png"
    assert quoted =~ "vana"
  end

  test "survives malformed markup" do
    assert {:ok, %{body: _, quoted: _}} = SplitQuoteHtml.run("<div><p>unclosed")
  end

  test "handles nil" do
    assert {:ok, %{body: "", quoted: nil}} = SplitQuoteHtml.run(nil)
  end
end
