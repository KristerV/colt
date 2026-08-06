defmodule Colt.Services.Email.RenderBodyTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Email.EnsureHtml
  alias Colt.Services.Email.RenderBody

  test "a Trix manual reply keeps its link" do
    # The body that prompted this work — stored fine, rendered as flat text.
    html =
      ~s(<div>Hei, olen ka puhkuselt tagasi. 5min ülevaade on siin: ) <>
        ~s(<a href="https://liid.ee/demo/features">https://liid.ee/demo/features</a>) <>
        ~s(<br><br>Krister<br>5635 5555</div>)

    assert {:ok, %{body: body, quoted: nil}} = RenderBody.run(html)
    assert body =~ ~s(<a href="https://liid.ee/demo/features">)
    assert body =~ "5635 5555"
  end

  test "a plain-text AI draft becomes HTML with real line breaks" do
    raw = "Tere Rene\n\nKas võin saata video?\n\nKrister\nhttps://liid.ee"

    assert {:ok, %{body: body}} = RenderBody.run(raw)
    assert body =~ ~r{<br\s*/?>}
    assert body =~ "Tere Rene"
    assert body =~ "Kas võin saata video?"
  end

  test "plain text keeps angle brackets that are not markup" do
    assert {:ok, %{body: body}} = RenderBody.run("Saada aadressile <rene@example.com>, kui a < b")
    assert body =~ "&lt;rene@example.com&gt;"
    assert body =~ "a &lt; b"
  end

  test "an inbound reply is split and sanitized in one pass" do
    html = """
    <div dir="ltr">Sobib, saada!<script>alert(1)</script></div>
    <div class="gmail_quote">
      <div class="gmail_attr">On Mon, Jun 15, 2026 Oscar wrote:</div>
      <blockquote class="gmail_quote">pitch</blockquote>
    </div>
    """

    assert {:ok, %{body: body, quoted: quoted}} = RenderBody.run(html)
    assert body =~ "Sobib, saada!"
    refute body =~ "alert(1)"
    refute body =~ "class="
    assert quoted =~ "pitch"
  end

  test "an empty body renders as nothing" do
    assert {:ok, %{body: "", quoted: nil}} = RenderBody.run("")
    assert {:ok, %{body: "", quoted: nil}} = RenderBody.run(nil)
  end

  test "EnsureHtml leaves real markup alone" do
    assert {:ok, "<p>x</p>"} = EnsureHtml.run("<p>x</p>")
  end
end
