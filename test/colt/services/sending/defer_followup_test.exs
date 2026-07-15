defmodule Colt.Services.Sending.DeferFollowupTest do
  @moduledoc """
  Covers the OOO rescheduling path — the deterministic parts, not the AI:

    * `CategorizeReply.defer_not_before/1` — the +3-after-return / +7-fallback rule
    * `OutboundEmail.next_scheduled_for_thread` — picks the soonest pending send
    * `DeferFollowup.run/2` — pushes that send out and leaves it :scheduled
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

  alias Colt.Services.Sending.{CategorizeReply, DeferFollowup}

  # A future Monday, used as the not_before lower bound. Picked far enough out
  # that NextSlot's "max(now, not_before)" always resolves to not_before.
  @not_before ~U[2026-09-14 00:00:00Z]

  describe "defer_not_before/1 (the OOO scheduling rule)" do
    test "schedules 3 days after a known return date, at start of that day (UTC)" do
      assert CategorizeReply.defer_not_before(~D[2026-07-10])
             |> DateTime.compare(~U[2026-07-13 00:00:00Z]) ==
               :eq
    end

    test "falls back to ~7 days from now when no return date is found" do
      before = DateTime.utc_now()
      result = CategorizeReply.defer_not_before(nil)
      seconds_out = DateTime.diff(result, before)

      # 7 days, give or take the few seconds of test execution.
      assert seconds_out >= 7 * 86_400 - 5
      assert seconds_out <= 7 * 86_400 + 5
    end
  end

  describe "next_scheduled_for_thread" do
    test "returns the soonest :scheduled send, ignoring :sent and :approved" do
      %{thread: thread, inbox: inbox} = graph(~U[2026-06-30 09:00:00Z])

      later =
        seed_email(thread, inbox,
          position: 2,
          status: :scheduled,
          scheduled_at: ~U[2026-07-05 09:00:00Z]
        )

      _earlier =
        seed_email(thread, inbox,
          position: 3,
          status: :scheduled,
          scheduled_at: ~U[2026-07-02 09:00:00Z]
        )

      _sent =
        seed_email(thread, inbox,
          position: 4,
          status: :sent,
          scheduled_at: ~U[2026-06-01 09:00:00Z]
        )

      _approved = seed_email(thread, inbox, position: 5, status: :approved, scheduled_at: nil)

      {:ok, row} = OutboundEmail.next_scheduled_for_thread(thread.id, authorize?: false)

      # The graph's own scheduled email (2026-06-30) is the soonest of all.
      refute row.id == later.id
      assert DateTime.compare(row.scheduled_at, ~U[2026-07-02 09:00:00Z]) == :lt
    end

    test "returns nil when the thread has no pending send" do
      %{thread: thread, email: email} = graph(~U[2026-06-30 09:00:00Z])
      {:ok, _} = OutboundEmail.mark_skipped(email, authorize?: false)

      assert {:ok, nil} =
               OutboundEmail.next_scheduled_for_thread(thread.id,
                 authorize?: false,
                 not_found_error?: false
               )
    end
  end

  describe "DeferFollowup.run/2" do
    test "pushes the next send to >= not_before and keeps it :scheduled" do
      %{thread: thread, email: email} = graph(~U[2026-06-30 09:00:00Z])

      assert {:ok, {:deferred, deferred_id, slot}} = DeferFollowup.run(thread.id, @not_before)
      assert deferred_id == email.id
      assert DateTime.compare(slot, @not_before) in [:gt, :eq]

      {:ok, reloaded} = OutboundEmail.get(email.id, authorize?: false)
      assert reloaded.status == :scheduled
      assert DateTime.compare(reloaded.scheduled_at, @not_before) in [:gt, :eq]
      # Lands inside a working hour (Mon–Fri 09:00–17:00 in the inbox tz).
      local = DateTime.shift_zone!(reloaded.scheduled_at, "Europe/Tallinn")
      assert Date.day_of_week(DateTime.to_date(local)) <= 5
      assert local.hour >= 9 and local.hour < 17
    end

    test "no-ops when there is nothing scheduled on the thread" do
      %{thread: thread, email: email} = graph(~U[2026-06-30 09:00:00Z])
      {:ok, _} = OutboundEmail.mark_skipped(email, authorize?: false)

      assert {:ok, :no_pending_send} = DeferFollowup.run(thread.id, @not_before)
    end
  end

  # ── fixtures (Ash.Seed bypasses create actions/policies/validations) ──

  defp graph(scheduled_at) do
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

    email = seed_email(thread, inbox, status: :scheduled, scheduled_at: scheduled_at)

    %{
      user: user,
      campaign: campaign,
      contact: contact,
      thread: thread,
      inbox: inbox,
      email: email
    }
  end

  # step_position is incidental to these tests, but one row per step per thread
  # is a DB invariant now, so each seeded row needs its own.
  defp seed_email(thread, inbox, opts) do
    Seed.seed!(OutboundEmail, %{
      thread_id: thread.id,
      email_account_id: inbox.id,
      step_position: Keyword.get(opts, :position, 1),
      status: Keyword.fetch!(opts, :status),
      scheduled_at: Keyword.get(opts, :scheduled_at)
    })
  end
end
