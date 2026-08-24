defmodule Colt.Services.Sending.SendOneRepliedGuardTest do
  @moduledoc """
  Regression for the delayed-classification incident (campaign
  547dd736-7d2c-4125-b6d0-1018f823d13d, contact replied 2026-06-18, reply
  classification only landed 2026-07-20 because PollInbounds silently
  missed it): a follow-up already loaded/queued for send must never go out
  once the contact has replied, no matter how late classification lands
  relative to `SendOne` picking the row up.

  Two independent gates now cover it — `guard_already_sent/1` (any
  terminal-but-not-:sent status) and `proceed_or_skip/1` (the contact's own
  `:replied` status) — so this covers both, plus the untouched happy path.
  """
  use Colt.DataCase, async: false

  alias Ash.Seed
  alias Colt.Accounts.User

  alias Colt.Resources.{
    Campaign,
    CampaignContact,
    Company,
    EmailAccount,
    OutboundEmail,
    Person,
    Thread
  }

  alias Colt.Services.Sending.SendOne

  describe "guard_already_sent (terminal outbound status)" do
    test "a :skipped row is left alone, not resent" do
      %{email: email} = graph(contact_status: :replied, email_status: :skipped)

      assert {:ok, :already_finalized} = SendOne.run(email.id)

      {:ok, reloaded} = OutboundEmail.get(email.id, authorize?: false)
      assert reloaded.status == :skipped
      assert reloaded.sent_at == nil
    end

    test "a :bounced row is left alone" do
      %{email: email} = graph(contact_status: :no_reply, email_status: :bounced)
      assert {:ok, :already_finalized} = SendOne.run(email.id)
    end

    test "a :failed row is left alone" do
      %{email: email} = graph(contact_status: :no_reply, email_status: :failed)
      assert {:ok, :already_finalized} = SendOne.run(email.id)
    end
  end

  describe "proceed_or_skip (contact already replied)" do
    test "a :scheduled row is skipped, not sent, when the contact has since replied" do
      %{email: email, campaign: campaign, contact: contact} =
        graph(contact_status: :replied, email_status: :scheduled)

      Colt.Services.Sending.Broadcast.subscribe(campaign.id)

      assert {:ok, :skipped_contact_replied} = SendOne.run(email.id)

      {:ok, reloaded} = OutboundEmail.get(email.id, authorize?: false)
      assert reloaded.status == :scheduled
      assert reloaded.sent_at == nil

      assert_receive {:email_skipped, email_id, contact_id, :contact_replied}
      assert email_id == email.id
      assert contact_id == contact.id
    end

    test "an :approved row is also skipped once replied" do
      %{email: email} = graph(contact_status: :replied, email_status: :approved)
      assert {:ok, :skipped_contact_replied} = SendOne.run(email.id)
    end
  end

  # ── fixtures (Ash.Seed bypasses create actions/policies/validations) ──

  defp graph(opts) do
    n = System.unique_integer([:positive])
    user = Seed.seed!(User, %{email: "owner-#{n}@liid.app"})
    company = Seed.seed!(Company, %{name: "Acme #{n}", registry_code: "EE#{n}", market: :ee})

    person =
      Seed.seed!(Person, %{name: "Mart Tamm", email: "mart-#{n}@acme.ee", company_id: company.id})

    campaign = Seed.seed!(Campaign, %{name: "Camp #{n}", owner_id: user.id})

    contact =
      Seed.seed!(CampaignContact, %{
        campaign_id: campaign.id,
        person_id: person.id,
        status: Keyword.fetch!(opts, :contact_status)
      })

    thread = Seed.seed!(Thread, %{campaign_contact_id: contact.id})

    inbox =
      Seed.seed!(EmailAccount, %{
        user_id: user.id,
        provider: :imap,
        address: "send-#{n}@liid.app",
        tz: "Europe/Tallinn",
        daily_quota: 50,
        status: :healthy
      })

    email =
      Seed.seed!(OutboundEmail, %{
        thread_id: thread.id,
        email_account_id: inbox.id,
        step_position: 2,
        status: Keyword.fetch!(opts, :email_status),
        ai_subject: "Following up",
        ai_body: "Just checking in."
      })

    %{
      user: user,
      campaign: campaign,
      contact: contact,
      thread: thread,
      inbox: inbox,
      email: email
    }
  end
end
