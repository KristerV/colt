defmodule Colt.Services.Sending.InjectOooWelcomeBackTest do
  @moduledoc """
  The admin-only OOO welcome-back injection (deterministic parts, not the AI):

    * a non-empty welcome-back is scheduled at not_before, and the pending
      follow-up is pushed out to after it (its normal delay past not_before),
      staying :scheduled as the sequence's continuation pointer
    * an empty / missing / already-sent welcome-back, or a contact whose
      snapshot has no OOO step, is skipped so the caller falls back to
      DeferFollowup
    * with no pending follow-up, the welcome-back still sends
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

  alias Colt.Services.Sending.InjectOooWelcomeBack

  @not_before ~U[2026-09-14 00:00:00Z]

  @snapshot_with_ooo %{
    "steps" => [
      %{"position" => -1, "kind" => "ooo", "delay_days" => 0},
      %{"position" => 0, "kind" => "email", "delay_days" => 0},
      %{"position" => 1, "kind" => "email", "delay_days" => 2},
      %{"position" => 2, "kind" => "terminal", "delay_days" => 7}
    ]
  }

  @snapshot_without_ooo %{
    "steps" => [
      %{"position" => 0, "kind" => "email", "delay_days" => 0},
      %{"position" => 1, "kind" => "email", "delay_days" => 2}
    ]
  }

  describe "run/3 — happy path" do
    test "schedules the welcome-back and pushes the follow-up out behind it" do
      %{contact: contact, thread: thread, inbox: inbox} = graph(@snapshot_with_ooo)

      ooo =
        seed_email(thread, inbox, step_position: -1, status: :approved, ai_body: "welcome back!")

      pending =
        seed_email(thread, inbox,
          step_position: 1,
          status: :scheduled,
          scheduled_at: ~U[2026-07-02 09:00:00Z]
        )

      assert {:ok, {:injected, ooo_id, slot}} =
               InjectOooWelcomeBack.run(thread.id, contact, @not_before)

      assert ooo_id == ooo.id
      assert DateTime.compare(slot, @not_before) in [:gt, :eq]

      {:ok, scheduled} = OutboundEmail.get(ooo.id, authorize?: false)
      assert scheduled.status == :scheduled
      assert DateTime.compare(scheduled.scheduled_at, @not_before) in [:gt, :eq]

      # The follow-up stays :scheduled but now lands strictly after the
      # welcome-back (its delay_days of 2 past not_before, snapped to a slot).
      {:ok, resumed} = OutboundEmail.get(pending.id, authorize?: false)
      assert resumed.status == :scheduled
      assert DateTime.compare(resumed.scheduled_at, scheduled.scheduled_at) == :gt
    end

    test "with no pending follow-up, still sends the welcome-back" do
      %{contact: contact, thread: thread, inbox: inbox} = graph(@snapshot_with_ooo)

      ooo =
        seed_email(thread, inbox, step_position: -1, status: :approved, ai_body: "welcome back!")

      assert {:ok, {:injected, ooo_id, _slot}} =
               InjectOooWelcomeBack.run(thread.id, contact, @not_before)

      assert ooo_id == ooo.id

      {:ok, scheduled} = OutboundEmail.get(ooo.id, authorize?: false)
      assert scheduled.status == :scheduled
    end
  end

  describe "run/3 — fallback (returns :no_welcome_back, leaves the thread untouched)" do
    test "when the welcome-back body is empty" do
      %{contact: contact, thread: thread, inbox: inbox} = graph(@snapshot_with_ooo)
      seed_email(thread, inbox, step_position: -1, status: :approved, ai_body: nil)

      pending =
        seed_email(thread, inbox,
          step_position: 1,
          status: :scheduled,
          scheduled_at: ~U[2026-07-02 09:00:00Z]
        )

      assert {:ok, :no_welcome_back} = InjectOooWelcomeBack.run(thread.id, contact, @not_before)

      # Pending follow-up is left as-is for the legacy DeferFollowup path.
      {:ok, untouched} = OutboundEmail.get(pending.id, authorize?: false)
      assert untouched.status == :scheduled
    end

    test "when the snapshot has no OOO step" do
      %{contact: contact, thread: thread, inbox: inbox} = graph(@snapshot_without_ooo)
      seed_email(thread, inbox, step_position: -1, status: :approved, ai_body: "welcome back!")

      seed_email(thread, inbox,
        step_position: 1,
        status: :scheduled,
        scheduled_at: ~U[2026-07-02 09:00:00Z]
      )

      assert {:ok, :no_welcome_back} = InjectOooWelcomeBack.run(thread.id, contact, @not_before)
    end

    test "when the welcome-back was already sent (one-shot per contact)" do
      %{contact: contact, thread: thread, inbox: inbox} = graph(@snapshot_with_ooo)
      seed_email(thread, inbox, step_position: -1, status: :sent, ai_body: "welcome back!")

      seed_email(thread, inbox,
        step_position: 1,
        status: :scheduled,
        scheduled_at: ~U[2026-07-02 09:00:00Z]
      )

      assert {:ok, :no_welcome_back} = InjectOooWelcomeBack.run(thread.id, contact, @not_before)
    end
  end

  # ── fixtures ──────────────────────────────────────────────────────────

  defp graph(snapshot) do
    n = System.unique_integer([:positive])
    user = Seed.seed!(User, %{email: "owner-#{n}@liid.app"})
    company = Seed.seed!(Company, %{name: "Acme #{n}", registry_code: "EE#{n}", market: :ee})

    person =
      Seed.seed!(Person, %{name: "Mart Tamm", email: "mart-#{n}@acme.ee", company_id: company.id})

    campaign = Seed.seed!(Campaign, %{name: "Camp #{n}", owner_id: user.id})

    inbox =
      Seed.seed!(EmailAccount, %{
        user_id: user.id,
        provider: :imap,
        address: "send-#{n}@liid.app",
        tz: "Europe/Tallinn",
        daily_quota: 50,
        status: :healthy
      })

    contact =
      Seed.seed!(CampaignContact, %{
        campaign_id: campaign.id,
        person_id: person.id,
        status: :sending,
        assigned_email_account_id: inbox.id,
        sequence_snapshot: snapshot
      })

    thread = Seed.seed!(Thread, %{campaign_contact_id: contact.id})

    %{user: user, campaign: campaign, contact: contact, thread: thread, inbox: inbox}
  end

  defp seed_email(thread, inbox, opts) do
    Seed.seed!(OutboundEmail, %{
      thread_id: thread.id,
      email_account_id: inbox.id,
      step_position: Keyword.fetch!(opts, :step_position),
      status: Keyword.fetch!(opts, :status),
      scheduled_at: Keyword.get(opts, :scheduled_at),
      ai_body: Keyword.get(opts, :ai_body)
    })
  end
end
