defmodule Colt.Resources.CampaignContactAssignInboxTest do
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignContact, Company, EmailAccount, Person}

  defp seed_user(email \\ "owner@example.com") do
    User
    |> Ash.Changeset.for_create(:seed, %{email: email}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp seed_contact(user) do
    {:ok, campaign} = Campaign.create_draft("Hunt", actor: user)

    {:ok, company} =
      Company.upsert_basic(
        %{
          registry_code: "12345678",
          market: :ee,
          name: "Acme OÜ",
          region: "Tallinn",
          status: :registered
        },
        actor: user,
        authorize?: false
      )

    {:ok, person} =
      Person.create_validated(
        %{company_id: company.id, name: "Mart Tamm", title: "CTO", email: "mart@acme.ee"},
        actor: user,
        authorize?: false
      )

    {:ok, contact} = CampaignContact.promote(campaign.id, person.id, actor: user)
    contact
  end

  defp seed_account(user) do
    EmailAccount.create_from_nylas(
      :imap,
      "robert@liidid.ee",
      "Robert Kuusk",
      "grant-#{System.unique_integer([:positive])}",
      "Europe/Tallinn",
      actor: user
    )
  end

  test "assign_inbox sets the sticky inbox without approving" do
    user = seed_user()
    contact = seed_contact(user)
    {:ok, account} = seed_account(user)

    assert contact.status == :pending_approval
    assert contact.assigned_email_account_id == nil

    {:ok, assigned} = CampaignContact.assign_inbox(contact, account.id, actor: user)

    assert assigned.assigned_email_account_id == account.id
    # Crucially: assignment alone must not flip status or stamp approved_at,
    # else the contact skips review and the load balancer miscounts.
    assert assigned.status == :pending_approval
    assert assigned.approved_at == nil
  end
end
