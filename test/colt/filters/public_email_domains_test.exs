defmodule Colt.Filters.PublicEmailDomainsTest do
  use ExUnit.Case, async: true

  alias Colt.Filters.PublicEmailDomains

  test "flags common webmail domains as public" do
    assert PublicEmailDomains.public?("gmail.com")
    assert PublicEmailDomains.public?("Gmail.com")
    assert PublicEmailDomains.public?("outlook.com")
    assert PublicEmailDomains.public?("icloud.com")
  end

  test "does not flag a company domain" do
    refute PublicEmailDomains.public?("acme.com")
  end

  test "nil is not public" do
    refute PublicEmailDomains.public?(nil)
  end
end
