defmodule Colt.Services.Enrichment.SuppressionTest do
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, SuppressedDomain}
  alias Colt.Services.Enrichment.Suppression

  describe "domain_from_url/1" do
    test "lowercases and strips www" do
      assert Suppression.domain_from_url("https://www.Acme.com/contact") == "acme.com"
    end

    test "keeps a real subdomain" do
      assert Suppression.domain_from_url("http://shop.acme.co.uk") == "shop.acme.co.uk"
    end

    test "nil for blank, nil, and unparseable input" do
      assert Suppression.domain_from_url(nil) == nil
      assert Suppression.domain_from_url("") == nil
      assert Suppression.domain_from_url("not a url") == nil
    end
  end

  describe "domain_from_email/1" do
    test "extracts and normalizes the domain" do
      assert Suppression.domain_from_email("  Foo@WWW.Acme.com ") == "acme.com"
    end

    test "nil when there's no usable @domain" do
      assert Suppression.domain_from_email("nope") == nil
      assert Suppression.domain_from_email("x@") == nil
      assert Suppression.domain_from_email(nil) == nil
    end
  end

  describe "domains_from_text/1 — format agnostic" do
    test "scans messy real-world rows and returns unique sorted domains" do
      lines = [
        "Email,First Name,Company",
        "me@asd.asd,Krister,Acme",
        "first;last;mister krister <BIG@Acme.com>;+372 5123",
        "\"quoted@beta.io\"\tTab\tStuff",
        "no email here at all",
        "two@gamma.io and also three@gamma.io same domain",
        "weird+tag@sub.delta.co.uk"
      ]

      assert Suppression.domains_from_text(lines) == [
               "acme.com",
               "asd.asd",
               "beta.io",
               "gamma.io",
               "sub.delta.co.uk"
             ]
    end

    test "empty when nothing looks like an email" do
      assert Suppression.domains_from_text(["name,phone", "Krister,5123"]) == []
    end
  end

  describe "excluded?/2" do
    setup do
      user =
        User
        |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
        |> Ash.create!(authorize?: false)

      {:ok, campaign} = Campaign.create_draft("Hunt", actor: user)
      {:ok, _} = SuppressedDomain.create(campaign.id, "acme.com", authorize?: false)

      %{campaign: campaign}
    end

    test "true when the website domain matches a suppressed domain", %{campaign: c} do
      assert Suppression.excluded?(c.id, "https://www.acme.com/about")
    end

    test "false for an un-suppressed domain", %{campaign: c} do
      refute Suppression.excluded?(c.id, "https://other.com")
    end

    test "false for nil/blank/unparseable url", %{campaign: c} do
      refute Suppression.excluded?(c.id, nil)
      refute Suppression.excluded?(c.id, "")
      refute Suppression.excluded?(c.id, "garbage")
    end

    test "scoped per campaign — another campaign's list doesn't leak", %{campaign: c} do
      user =
        User
        |> Ash.Changeset.for_create(:seed, %{email: "other@example.com"}, authorize?: false)
        |> Ash.create!(authorize?: false)

      {:ok, other} = Campaign.create_draft("Other", actor: user)

      refute Suppression.excluded?(other.id, "https://www.acme.com")
      assert Suppression.excluded?(c.id, "https://www.acme.com")
    end
  end

  describe "SuppressedDomain upsert" do
    setup do
      user =
        User
        |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
        |> Ash.create!(authorize?: false)

      {:ok, campaign} = Campaign.create_draft("Hunt", actor: user)
      %{campaign: campaign}
    end

    test "re-inserting the same domain is idempotent", %{campaign: c} do
      {:ok, _} = SuppressedDomain.create(c.id, "acme.com", authorize?: false)
      {:ok, _} = SuppressedDomain.create(c.id, "acme.com", authorize?: false)

      assert {:ok, [%{domain: "acme.com"}]} =
               SuppressedDomain.list_for_campaign(c.id, authorize?: false)
    end
  end
end
