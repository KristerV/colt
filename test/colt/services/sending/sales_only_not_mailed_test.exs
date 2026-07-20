defmodule Colt.Services.Sending.SalesOnlyNotMailedTest do
  @moduledoc """
  Regression: hand-entered sales-only contacts must never enter the send
  machine.

  `status` defaults to `:pending_approval` on every CampaignContact, including
  leads created straight into the sales funnel — people already being talked to
  by phone. `next_pending` once filtered on status alone, so the auto-approve
  loop drained those leads ahead of the enriched pool and mailed them a
  sequence. Two guards now stand between them and an email: the read's funnel
  clause, and AutoDraftAndApprove's own check.
  """

  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignContact, Company, Person}
  alias Colt.Services.Sales.CreateManualContact
  alias Colt.Services.Sending.AutoDraftAndApprove

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp seed_campaign(user) do
    {:ok, campaign} = Campaign.create_draft("Hunt", actor: user)
    campaign
  end

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

  defp sales_only_contact(campaign, user) do
    {:ok, contact} =
      CreateManualContact.run(
        campaign.id,
        %{
          name: "Ergo Olek",
          company_name: "Kohvik OÜ",
          registry_code: "20000002",
          market: :ee,
          in_funnel_sending?: false,
          in_funnel_sales?: true
        },
        actor: user
      )

    contact
  end

  describe "next_pending" do
    test "skips a sales-only manual contact even though its status is :pending_approval" do
      user = seed_user()
      campaign = seed_campaign(user)

      sales_only = sales_only_contact(campaign, user)

      # The trap: it really is pending_approval, it's just not for sending.
      assert sales_only.status == :pending_approval
      assert sales_only.in_funnel_sending? == false

      assert {:error, _} = CampaignContact.next_pending(campaign.id, actor: user)
    end

    test "still returns an enrichment contact, and never prefers the older sales-only one" do
      user = seed_user()
      campaign = seed_campaign(user)

      # Created first, so an inserted_at-ascending sort would surface it first.
      sales_only = sales_only_contact(campaign, user)
      enriched = promote_enriched(campaign, user)

      assert {:ok, picked} = CampaignContact.next_pending(campaign.id, actor: user)
      assert picked.id == enriched.id
      refute picked.id == sales_only.id
    end
  end

  describe "any_committed_for_campaign" do
    test "an approved sales-only contact does not unlock auto-approve" do
      user = seed_user()
      campaign = seed_campaign(user)

      contact = sales_only_contact(campaign, user)

      {:ok, _} = CampaignContact.set_status(contact, :replied, actor: user)

      assert {:ok, []} = CampaignContact.any_committed_for_campaign(campaign.id, actor: user)
    end
  end

  describe "AutoDraftAndApprove" do
    test "refuses a sales-only contact regardless of how it was handed over" do
      user = seed_user()
      campaign = seed_campaign(user)

      contact = sales_only_contact(campaign, user)

      assert {:error, :not_in_sending_funnel} =
               AutoDraftAndApprove.run(contact.id, actor: user)
    end

    test "the refusal happens before any draft is written" do
      user = seed_user()
      campaign = seed_campaign(user)

      contact = sales_only_contact(campaign, user)

      {:error, :not_in_sending_funnel} = AutoDraftAndApprove.run(contact.id, actor: user)

      loaded = Ash.get!(CampaignContact, contact.id, load: [:thread], authorize?: false)

      assert loaded.status == :pending_approval
      assert loaded.approved_at == nil
      assert loaded.auto_approved? == false

      {:ok, emails} =
        Colt.Resources.OutboundEmail.list_for_thread(loaded.thread.id, authorize?: false)

      assert emails == []
    end
  end
end
