defmodule Colt.Services.Sending.LastThreadMessageIdTest do
  use Colt.DataCase, async: false

  alias Ash.Seed
  alias Colt.Accounts.User

  alias Colt.Resources.{
    Campaign,
    CampaignContact,
    Company,
    EmailAccount,
    InboundEmail,
    OutboundEmail,
    Person,
    Thread
  }

  alias Colt.Services.Sending.LastThreadMessageId

  describe "run/1" do
    test "prefers the most recent inbound reply over any outbound send" do
      %{thread: thread, inbox: inbox} = graph()

      seed_outbound(thread, inbox,
        step_position: 1,
        status: :sent,
        nylas_message_id: "out-1",
        sent_at: ~U[2026-07-01 09:00:00Z]
      )

      seed_inbound(thread, inbox,
        nylas_message_id: "in-1",
        received_at: ~U[2026-07-02 09:00:00Z]
      )

      assert {:ok, "in-1"} = LastThreadMessageId.run(thread.id)
    end

    test "falls back to the most recently sent outbound when there's no inbound reply" do
      %{thread: thread, inbox: inbox} = graph()

      seed_outbound(thread, inbox,
        step_position: 1,
        status: :sent,
        nylas_message_id: "out-1",
        sent_at: ~U[2026-07-01 09:00:00Z]
      )

      seed_outbound(thread, inbox,
        step_position: 2,
        status: :sent,
        nylas_message_id: "out-2",
        sent_at: ~U[2026-07-05 09:00:00Z]
      )

      assert {:ok, "out-2"} = LastThreadMessageId.run(thread.id)
    end

    test "ignores outbound rows that aren't sent or have no nylas_message_id" do
      %{thread: thread, inbox: inbox} = graph()

      seed_outbound(thread, inbox,
        step_position: 1,
        status: :sent,
        nylas_message_id: "out-1",
        sent_at: ~U[2026-07-01 09:00:00Z]
      )

      seed_outbound(thread, inbox,
        step_position: 2,
        status: :scheduled,
        nylas_message_id: nil,
        sent_at: nil
      )

      assert {:ok, "out-1"} = LastThreadMessageId.run(thread.id)
    end

    test "returns nil when the thread has no messages yet" do
      %{thread: thread} = graph()

      assert {:ok, nil} = LastThreadMessageId.run(thread.id)
    end
  end

  defp graph do
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
        status: :sending
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

    %{user: user, campaign: campaign, contact: contact, thread: thread, inbox: inbox}
  end

  defp seed_outbound(thread, inbox, opts) do
    Seed.seed!(OutboundEmail, %{
      thread_id: thread.id,
      email_account_id: inbox.id,
      step_position: Keyword.fetch!(opts, :step_position),
      status: Keyword.fetch!(opts, :status),
      nylas_message_id: Keyword.get(opts, :nylas_message_id),
      sent_at: Keyword.get(opts, :sent_at)
    })
  end

  defp seed_inbound(thread, inbox, opts) do
    n = System.unique_integer([:positive])

    Seed.seed!(InboundEmail, %{
      thread_id: thread.id,
      email_account_id: inbox.id,
      from_address: Keyword.get(opts, :from_address, "mart-#{n}@acme.ee"),
      nylas_message_id: Keyword.fetch!(opts, :nylas_message_id),
      received_at: Keyword.fetch!(opts, :received_at)
    })
  end
end
