defmodule Colt.Services.Sales.UpdateContactTest do
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignContact, EmailAccount}
  alias Colt.Services.Sales.{CreateManualContact, UpdateContact}

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp seed_campaign(user) do
    {:ok, campaign} = Campaign.create_draft("Hunt", actor: user)
    campaign
  end

  defp seed_email_account(user, address) do
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

  # A hand-entered sales contact, optionally pre-seeded with a send-from inbox.
  defp manual_contact(campaign, user, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Jane Tamm",
          company_name: "Kohvik OÜ",
          registry_code: "20000002",
          market: :ee,
          in_funnel_sending?: false,
          in_funnel_sales?: true
        },
        overrides
      )

    {:ok, contact} = CreateManualContact.run(campaign.id, attrs, actor: user)
    Ash.get!(CampaignContact, contact.id, load: [person: :company], authorize?: false)
  end

  # UpdateContact reads the same shape the edit form submits.
  defp edit_attrs(overrides) do
    Map.merge(
      %{
        name: "Jane Tamm",
        company_name: "Kohvik OÜ",
        registry_code: "20000002",
        market: :ee,
        in_funnel_sending?: false,
        in_funnel_sales?: true
      },
      overrides
    )
  end

  test "seeds the send-from inbox when the contact has none" do
    user = seed_user()
    campaign = seed_campaign(user)
    inbox = seed_email_account(user, "seed@liid.test")

    contact = manual_contact(campaign, user)
    assert contact.assigned_email_account_id == nil

    {:ok, updated} =
      UpdateContact.run(contact, edit_attrs(%{assigned_email_account_id: inbox.id}), actor: user)

    assert updated.assigned_email_account_id == inbox.id
  end

  test "sticks to the inbox already in use — an assigned sender is never overwritten" do
    user = seed_user()
    campaign = seed_campaign(user)
    first = seed_email_account(user, "first@liid.test")
    second = seed_email_account(user, "second@liid.test")

    contact = manual_contact(campaign, user, %{assigned_email_account_id: first.id})
    assert contact.assigned_email_account_id == first.id

    {:ok, updated} =
      UpdateContact.run(contact, edit_attrs(%{assigned_email_account_id: second.id}), actor: user)

    assert updated.assigned_email_account_id == first.id
  end

  test "adds a missing email so the contact becomes replyable" do
    user = seed_user()
    campaign = seed_campaign(user)

    contact = manual_contact(campaign, user)
    assert contact.person.email == nil

    {:ok, _updated} =
      UpdateContact.run(contact, edit_attrs(%{email: "jane@kohvik.test"}), actor: user)

    reloaded = Ash.get!(CampaignContact, contact.id, load: [:person], authorize?: false)
    assert reloaded.person.email == "jane@kohvik.test"
  end
end
