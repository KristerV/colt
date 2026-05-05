defmodule Colt.Services.Enrichment.ExtractGenericEmailTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Enrichment.ExtractGenericEmail

  test "matches a generic mailbox on the host" do
    html = ~s|<p>Reach us: <a href="mailto:hello@acme.io">Hello</a></p>|
    assert {:ok, "hello@acme.io"} = ExtractGenericEmail.run(html, "acme.io")
  end

  test "matches subdomain of host" do
    html = "Sales: sales@eu.acme.io"
    assert {:ok, "sales@eu.acme.io"} = ExtractGenericEmail.run(html, "acme.io")
  end

  test "ignores mailboxes on other domains" do
    html = "support@otherdomain.com"
    assert {:ok, nil} = ExtractGenericEmail.run(html, "acme.io")
  end

  test "ignores personal-name addresses" do
    html = "alice@acme.io"
    assert {:ok, nil} = ExtractGenericEmail.run(html, "acme.io")
  end
end
