defmodule Colt.Services.Enrichment.ClassifyEmailAddressTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Enrichment.ClassifyEmailAddress

  describe "keyword pass (no model)" do
    test "known shared-inbox prefixes resolve without a model call" do
      for email <- ~w(info@acme.io kontakt@acme.io sales@acme.io arved@acme.ee) do
        assert {:ok, :generic} = ClassifyEmailAddress.run(email)
      end
    end

    test "non-addresses are generic rather than crashing" do
      assert {:ok, :generic} = ClassifyEmailAddress.run("")
      assert {:ok, :generic} = ClassifyEmailAddress.run(nil)
      assert {:ok, :generic} = ClassifyEmailAddress.run("@acme.io")
    end
  end

  # These hit the live model. `mix test --only eval`.
  describe "model pass" do
    @describetag :eval

    test "reads Estonian first names as people" do
      for email <- ~w(andres@ettevote.ee toomas@firma.ee aare.kulli@gmail.com soobik@sopser.ee) do
        assert {:ok, :personal} = ClassifyEmailAddress.run(email), "expected #{email} personal"
      end
    end

    test "initials on a company domain are a person" do
      assert {:ok, :personal} = ClassifyEmailAddress.run("hg@krafteer.com")
    end

    test "a free-provider domain does not make an address generic" do
      assert {:ok, :personal} = ClassifyEmailAddress.run("janika.vahtra@gmail.com")
    end

    test "company names and registry codes are not people" do
      for email <- ~w(oravasolutions@gmail.com valasteagro@gmail.com 14614272@mail.ee) do
        assert {:ok, :generic} = ClassifyEmailAddress.run(email), "expected #{email} generic"
      end
    end

    test "creative Estonian shared inboxes are generic" do
      for email <- ~w(tere@firma.ee pood@firma.ee kontor@firma.ee) do
        assert {:ok, :generic} = ClassifyEmailAddress.run(email), "expected #{email} generic"
      end
    end
  end
end
