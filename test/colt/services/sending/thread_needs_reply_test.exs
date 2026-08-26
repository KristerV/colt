defmodule Colt.Services.Sending.ThreadNeedsReplyTest do
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

  alias Colt.Services.Sending.ThreadNeedsReply

  describe "run/1" do
    test "false when there's no inbound reply yet" do
      %{thread: thread, inbox: inbox} = graph()

      seed_outbound(thread, inbox,
        step_position: 1,
        status: :sent,
        sent_at: ~U[2026-07-01 09:00:00Z]
      )

      assert {:ok, false} = ThreadNeedsReply.run(thread.id)
    end

    test "true when they replied and we've never sent anything" do
      %{thread: thread, inbox: inbox} = graph()

      seed_inbound(thread, inbox, received_at: ~U[2026-07-01 09:00:00Z])

      assert {:ok, true} = ThreadNeedsReply.run(thread.id)
    end

    test "true when their reply is newer than our last send" do
      %{thread: thread, inbox: inbox} = graph()

      seed_outbound(thread, inbox,
        step_position: 1,
        status: :sent,
        sent_at: ~U[2026-07-01 09:00:00Z]
      )

      seed_inbound(thread, inbox, received_at: ~U[2026-07-02 09:00:00Z])

      assert {:ok, true} = ThreadNeedsReply.run(thread.id)
    end

    test "false once we've sent something after their reply" do
      %{thread: thread, inbox: inbox} = graph()

      seed_outbound(thread, inbox,
        step_position: 1,
        status: :sent,
        sent_at: ~U[2026-07-01 09:00:00Z]
      )

      seed_inbound(thread, inbox, received_at: ~U[2026-07-02 09:00:00Z])

      seed_outbound(thread, inbox,
        step_position: nil,
        status: :sent,
        sent_at: ~U[2026-07-03 09:00:00Z]
      )

      assert {:ok, false} = ThreadNeedsReply.run(thread.id)
    end

    test "true again if they reply after we answer" do
      %{thread: thread, inbox: inbox} = graph()

      seed_outbound(thread, inbox,
        step_position: 1,
        status: :sent,
        sent_at: ~U[2026-07-01 09:00:00Z]
      )

      seed_inbound(thread, inbox, received_at: ~U[2026-07-02 09:00:00Z])

      seed_outbound(thread, inbox,
        step_position: nil,
        status: :sent,
        sent_at: ~U[2026-07-03 09:00:00Z]
      )

      seed_inbound(thread, inbox, received_at: ~U[2026-07-04 09:00:00Z])

      assert {:ok, true} = ThreadNeedsReply.run(thread.id)
    end

    test "an unsent scheduled/drafted outbound doesn't count as answering" do
      %{thread: thread, inbox: inbox} = graph()

      seed_outbound(thread, inbox,
        step_position: 1,
        status: :sent,
        sent_at: ~U[2026-07-01 09:00:00Z]
      )

      seed_inbound(thread, inbox, received_at: ~U[2026-07-02 09:00:00Z])

      seed_outbound(thread, inbox, step_position: nil, status: :scheduled, sent_at: nil)

      assert {:ok, true} = ThreadNeedsReply.run(thread.id)
    end

    test "false when the thread has no messages yet" do
      %{thread: thread} = graph()

      assert {:ok, false} = ThreadNeedsReply.run(thread.id)
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
    n = System.unique_integer([:positive])

    Seed.seed!(OutboundEmail, %{
      thread_id: thread.id,
      email_account_id: inbox.id,
      step_position: Keyword.get(opts, :step_position),
      status: Keyword.fetch!(opts, :status),
      nylas_message_id: "out-#{n}",
      sent_at: Keyword.get(opts, :sent_at)
    })
  end

  defp seed_inbound(thread, inbox, opts) do
    n = System.unique_integer([:positive])

    Seed.seed!(InboundEmail, %{
      thread_id: thread.id,
      email_account_id: inbox.id,
      from_address: Keyword.get(opts, :from_address, "mart-#{n}@acme.ee"),
      nylas_message_id: "in-#{n}",
      received_at: Keyword.fetch!(opts, :received_at)
    })
  end
end
