defmodule Colt.Services.Sales.CreateManualContactTest do
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignContact, Company, EmailAccount, Person}
  alias Colt.Services.Sales.CreateManualContact

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp seed_email_account(user, address \\ "sender@liid.test") do
    {:ok, account} =
      EmailAccount.create_from_nylas(
        :google,
        address,
        "Sender",
        "grant-#{System.unique_integer([:positive])}",
        "Europe/Tallinn",
        actor: user,
        authorize?: false
      )

    account
  end

  defp seed_campaign(user) do
    {:ok, campaign} = Campaign.create_draft("Hunt", actor: user)
    campaign
  end

  # A normal enrichment-promoted contact, for the origin/flag defaults.
  defp promote_enriched(campaign, user) do
    {:ok, company} =
      Company.upsert_basic(
        %{registry_code: "10000001", market: :ee, name: "Acme OÜ", status: :registered},
        actor: user,
        authorize?: false
      )

    {:ok, person} =
      Person.create_validated(%{company_id: company.id, name: "Mart"},
        actor: user,
        authorize?: false
      )

    {:ok, contact} = CampaignContact.promote(campaign.id, person.id, actor: user)
    contact
  end

  defp base_attrs(overrides) do
    Map.merge(
      %{
        name: "Jane Tamm",
        company_name: "Kohvik OÜ",
        registry_code: "20000002",
        market: :ee,
        in_funnel_sending?: false,
        in_funnel_sales?: false
      },
      overrides
    )
  end

  describe "origin" do
    test "an enrichment-promoted contact defaults to origin :enrichment, sending on, sales off" do
      user = seed_user()
      campaign = seed_campaign(user)

      contact = promote_enriched(campaign, user)

      assert contact.origin == :enrichment
      assert contact.in_funnel_sending? == true
      assert contact.in_funnel_sales? == false
    end

    test "a manually created contact is origin :manual" do
      user = seed_user()
      campaign = seed_campaign(user)

      {:ok, contact} =
        CreateManualContact.run(campaign.id, base_attrs(%{in_funnel_sales?: true}), actor: user)

      assert contact.origin == :manual
    end
  end

  describe "funnel flags" do
    test "sales-only manual contact: in sales funnel, absent from sending, lands in first stage" do
      user = seed_user()
      campaign = seed_campaign(user)

      {:ok, contact} =
        CreateManualContact.run(
          campaign.id,
          base_attrs(%{in_funnel_sales?: true, in_funnel_sending?: false}),
          actor: user
        )

      loaded =
        Ash.get!(CampaignContact, contact.id, load: [:sales_stage], authorize?: false)

      assert loaded.in_funnel_sales? == true
      assert loaded.in_funnel_sending? == false
      assert loaded.sales_stage != nil
      assert loaded.sales_stage.kind == :active

      {:ok, sending} = CampaignContact.list_for_campaign(campaign.id, actor: user)
      {:ok, sales} = CampaignContact.list_entered_for_campaign(campaign.id, actor: user)

      refute Enum.any?(sending, &(&1.id == contact.id))
      assert Enum.any?(sales, &(&1.id == contact.id))
    end

    test "sending-only manual contact: in sending, absent from sales, no stage" do
      user = seed_user()
      campaign = seed_campaign(user)

      {:ok, contact} =
        CreateManualContact.run(
          campaign.id,
          base_attrs(%{in_funnel_sales?: false, in_funnel_sending?: true}),
          actor: user
        )

      assert contact.in_funnel_sending? == true
      assert contact.in_funnel_sales? == false
      assert contact.sales_stage_id == nil

      {:ok, sending} = CampaignContact.list_for_campaign(campaign.id, actor: user)
      {:ok, sales} = CampaignContact.list_entered_for_campaign(campaign.id, actor: user)

      assert Enum.any?(sending, &(&1.id == contact.id))
      refute Enum.any?(sales, &(&1.id == contact.id))
    end

    test "entering the sales funnel flips in_funnel_sales? for an existing sending contact" do
      user = seed_user()
      campaign = seed_campaign(user)

      contact = promote_enriched(campaign, user)
      assert contact.in_funnel_sales? == false

      {:ok, _} = Colt.Services.Sales.AutoEnter.run(contact.id, campaign.id, actor: user)

      reloaded = Ash.get!(CampaignContact, contact.id, authorize?: false)
      assert reloaded.in_funnel_sales? == true
      assert reloaded.in_funnel_sending? == true
      assert reloaded.sales_stage_id != nil
    end

    test "creates the person and its manual company from the form fields" do
      user = seed_user()
      campaign = seed_campaign(user)

      {:ok, contact} =
        CreateManualContact.run(
          campaign.id,
          base_attrs(%{
            name: "Liis Kask",
            company_name: "AS Näide",
            registry_code: "30000003",
            market: :fi,
            in_funnel_sales?: true
          }),
          actor: user
        )

      loaded =
        Ash.get!(CampaignContact, contact.id, load: [person: :company], authorize?: false)

      assert loaded.person.name == "Liis Kask"
      assert loaded.person.company.name == "AS Näide"
      assert loaded.person.company.registry_code == "30000003"
      assert loaded.person.company.market == :fi
    end
  end

  describe "send-from inbox" do
    test "stores the picked inbox as the sticky sender the reply path uses" do
      user = seed_user()
      campaign = seed_campaign(user)
      inbox = seed_email_account(user)

      {:ok, contact} =
        CreateManualContact.run(
          campaign.id,
          base_attrs(%{in_funnel_sales?: true, assigned_email_account_id: inbox.id}),
          actor: user
        )

      assert contact.assigned_email_account_id == inbox.id
    end

    test "defaults to no sender when none is picked (not every contact is emailed)" do
      user = seed_user()
      campaign = seed_campaign(user)

      {:ok, contact} =
        CreateManualContact.run(campaign.id, base_attrs(%{in_funnel_sales?: true}), actor: user)

      assert contact.assigned_email_account_id == nil
    end
  end
end
