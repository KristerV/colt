defmodule Colt.Services.Email.HtmlToTextTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Email.HtmlToText

  test "drops style contents, not just the tags" do
    html = "<style>v\\:* {behavior:url(#default#VML);}</style><p>Tere</p>"
    assert {:ok, "Tere"} = HtmlToText.run(html)
  end

  test "drops script, head and meta subtrees" do
    html = "<head><title>Ignore</title><meta content='x'></head><body><p>Keep</p></body>"
    assert {:ok, "Keep"} = HtmlToText.run(html)
  end

  test "decodes entities including nbsp" do
    assert {:ok, "Täname a & b"} = HtmlToText.run("<p>T&auml;name&nbsp;a &amp; b</p>")
  end

  test "block elements become line breaks" do
    assert {:ok, "one\n\ntwo"} = HtmlToText.run("<p>one</p><p>two</p>")
    assert {:ok, "one\ntwo"} = HtmlToText.run("one<br>two")
  end

  test "collapses runs of blank lines" do
    assert {:ok, "a\n\nb"} = HtmlToText.run("<p>a</p><p></p><p></p><p>b</p>")
  end

  test "plain text passes through untouched" do
    assert {:ok, "Tere Rene\n\nKrister"} = HtmlToText.run("Tere Rene\n\nKrister")
  end

  test "handles nil and non-binary input" do
    assert {:ok, ""} = HtmlToText.run(nil)
  end
end
