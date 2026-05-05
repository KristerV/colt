defmodule Colt.Services.Enrichment.ValidateInMarkdownTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Enrichment.ValidateInMarkdown

  test "case-insensitive substring match" do
    md = "Reach me at Alice@ACME.io anytime."
    assert {:ok, true} = ValidateInMarkdown.run("alice@acme.io", md)
  end

  test "missing email → false" do
    assert {:ok, false} = ValidateInMarkdown.run("ghost@nowhere.com", "some text")
  end

  test "blank email → false" do
    assert {:ok, false} = ValidateInMarkdown.run("", "stuff")
    assert {:ok, false} = ValidateInMarkdown.run(nil, "stuff")
  end
end
