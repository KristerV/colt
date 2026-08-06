defmodule Colt.Services.Email.SanitizeHtmlTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Email.SanitizeHtml

  test "keeps ordinary formatting and links" do
    html =
      ~s(<div>Hei <strong>Rene</strong>, <a href="https://liid.ee/demo">vaata</a><br>Krister</div>)

    assert {:ok, out} = SanitizeHtml.run(html)
    assert out =~ ~s(<a href="https://liid.ee/demo">vaata</a>)
    assert out =~ "<strong>Rene</strong>"
    assert out =~ "<br"
  end

  test "drops scripts with their contents" do
    assert {:ok, out} = SanitizeHtml.run(~s|<p>ok</p><script>alert(1)</script>|)
    assert out == "<p>ok</p>"
  end

  test "drops style blocks rather than leaking their CSS as text" do
    assert {:ok, out} = SanitizeHtml.run("<style>.x{color:red}</style><p>ok</p>")
    refute out =~ "color:red"
  end

  test "strips event handlers" do
    assert {:ok, out} = SanitizeHtml.run(~s|<div onclick="alert(1)" onmouseover="x()">hi</div>|)
    refute out =~ "onclick"
    refute out =~ "onmouseover"
  end

  test "drops javascript: and data:text/html urls but keeps the text" do
    assert {:ok, out} = SanitizeHtml.run(~s|<a href="javascript:alert(1)">click</a>|)
    refute out =~ "javascript:"
    assert out =~ "click"

    assert {:ok, out} = SanitizeHtml.run(~s(<a href="data:text/html;base64,PHN2Zz4=">x</a>))
    refute out =~ "data:text/html"
  end

  test "keeps mailto, tel, cid, relative and inline-image urls" do
    for url <- [
          "mailto:rene@example.com",
          "tel:+3725635555",
          "cid:logo@liid",
          "/campaigns/1",
          "data:image/png;base64,iVBORw0KGgo="
        ] do
      assert {:ok, out} = SanitizeHtml.run(~s(<a href="#{url}">x</a><img src="#{url}">))
      assert out =~ url, "expected #{url} to survive"
    end
  end

  test "keeps a query string that happens to contain a colon" do
    assert {:ok, out} = SanitizeHtml.run(~s(<a href="/search?t=12:30">x</a>))
    assert out =~ "12:30"
  end

  test "drops class and id so foreign markup cannot reach our selectors" do
    assert {:ok, out} = SanitizeHtml.run(~s(<div class="email-html" id="main">hi</div>))
    refute out =~ "class"
    refute out =~ "id="
  end

  test "filters style down to presentational properties" do
    html =
      ~s|<div style="color: #b00; position: fixed; background-image: url(http://x/p.gif)">hi</div>|

    assert {:ok, out} = SanitizeHtml.run(html)
    assert out =~ "color: #b00"
    refute out =~ "position"
    refute out =~ "url("
  end

  test "unwraps unknown tags but keeps their text" do
    assert {:ok, out} = SanitizeHtml.run("<marquee>hello</marquee>")
    assert out == "hello"
  end

  test "escapes text that looks like markup" do
    assert {:ok, out} = SanitizeHtml.run("<p>a &lt;script&gt;b&lt;/script&gt; c</p>")
    refute out =~ "<script>"
    assert out =~ "&lt;script&gt;"
  end

  test "nil passes through so an absent quoted half stays absent" do
    assert {:ok, nil} = SanitizeHtml.run(nil)
  end
end
