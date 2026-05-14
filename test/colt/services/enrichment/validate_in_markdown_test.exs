defmodule Colt.Services.Enrichment.ValidateInMarkdownTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Enrichment.ValidateInMarkdown

  test "case-insensitive substring match" do
    md = "Reach me at Alice@ACME.io anytime."
    assert {:ok, true} = ValidateInMarkdown.run("alice@acme.io", md)
  end

  test "fuzzy match between local and domain (obfuscated emails)" do
    assert {:ok, true} = ValidateInMarkdown.run("alice@acme.io", "alice [at] acme.io")
    assert {:ok, true} = ValidateInMarkdown.run("alice@acme.io", "alice (at) acme.io")
    assert {:ok, true} = ValidateInMarkdown.run("alice@acme.io", "alice&#64;acme.io")
    assert {:ok, true} = ValidateInMarkdown.run("alice@acme.io", "alice @ acme.io")
    # "dot" obfuscation isn't handled — domain must appear literally
    assert {:ok, false} = ValidateInMarkdown.run("alice@acme.io", "alice at acme dot io")
  end

  test "gap longer than 10 chars → false" do
    md = "alice ............... acme.io"
    assert {:ok, false} = ValidateInMarkdown.run("alice@acme.io", md)
  end

  test "missing email → false" do
    assert {:ok, false} = ValidateInMarkdown.run("ghost@nowhere.com", "some text")
  end

  test "blank email → false" do
    assert {:ok, false} = ValidateInMarkdown.run("", "stuff")
    assert {:ok, false} = ValidateInMarkdown.run(nil, "stuff")
  end

  describe "run_phone/2" do
    test "exact match" do
      assert {:ok, true} = ValidateInMarkdown.run_phone("+3725551234", "call +3725551234 today")
    end

    test "whitespace differences are ignored on both sides" do
      assert {:ok, true} = ValidateInMarkdown.run_phone("+372 555 1234", "call +3725551234 today")
      assert {:ok, true} = ValidateInMarkdown.run_phone("+3725551234", "call +372 555 1234 today")
      assert {:ok, true} = ValidateInMarkdown.run_phone("+372 555 1234", "tel: +372\t555\n1234")
    end

    test "plus sign is ignored on both sides" do
      assert {:ok, true} = ValidateInMarkdown.run_phone("+3725551234", "call 3725551234")
      assert {:ok, true} = ValidateInMarkdown.run_phone("3725551234", "call +372 555 1234")
    end

    test "missing number → false" do
      assert {:ok, false} = ValidateInMarkdown.run_phone("+3729999999", "call +3725551234")
    end

    test "blank phone → false" do
      assert {:ok, false} = ValidateInMarkdown.run_phone("", "+3725551234")
      assert {:ok, false} = ValidateInMarkdown.run_phone(nil, "+3725551234")
      assert {:ok, false} = ValidateInMarkdown.run_phone("   ", "+3725551234")
    end
  end
end
