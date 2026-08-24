defmodule Colt.Services.Sending.RecordPollOutcomeTest do
  @moduledoc """
  Regression: `last_sync_at` (the message cursor) advances even on an empty
  page, so it can't answer "is polling actually working." These fields are
  the decoupled signal that would have caught the 8-week silent-fail window
  (2026-05-27 to 2026-07-20) — a chronically-failing account should show a
  growing `poll_failure_count` and a stale `last_poll_success_at` regardless
  of what `last_sync_at` says.
  """
  use Colt.DataCase, async: false

  alias Ash.Seed
  alias Colt.Accounts.User
  alias Colt.Resources.EmailAccount
  alias Colt.Services.Sending.RecordPollOutcome

  defp seed_account do
    n = System.unique_integer([:positive])
    user = Seed.seed!(User, %{email: "owner-#{n}@liid.app"})

    Seed.seed!(EmailAccount, %{
      user_id: user.id,
      provider: :imap,
      address: "inbox-#{n}@liid.app",
      tz: "Europe/Tallinn",
      status: :healthy
    })
  end

  test "a success clears the failure streak" do
    account = seed_account()
    {:ok, failing} = RecordPollOutcome.run(account, {:error, :boom})
    {:ok, failing} = RecordPollOutcome.run(failing, {:error, :boom})
    assert failing.poll_failure_count == 2

    {:ok, healed} = RecordPollOutcome.run(failing, :ok)
    assert healed.poll_failure_count == 0
    assert healed.last_poll_error_at == nil
    assert healed.last_poll_success_at != nil
  end

  test "repeated failures increment the streak and stamp the error time" do
    account = seed_account()

    {:ok, once} = RecordPollOutcome.run(account, {:error, :no_inbox_folder})
    assert once.poll_failure_count == 1
    assert once.last_poll_error_at != nil

    {:ok, twice} = RecordPollOutcome.run(once, {:error, :no_inbox_folder})
    assert twice.poll_failure_count == 2
  end
end
