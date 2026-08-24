defmodule Colt.Services.Sending.RecordPollOutcome do
  @moduledoc """
  Stamp an `EmailAccount` with the result of one inbound-poll attempt.

  Decoupled from `last_sync_at` (the message cursor, which only advances on
  a successful fetch) so `last_poll_success_at`/`poll_failure_count` answer
  "is polling actually working" independent of "how far back has it read" —
  the two silently diverged for 8 weeks (2026-05-27 to 2026-07-20) with
  nothing to show for it.
  """

  alias Colt.Resources.EmailAccount

  def run(%EmailAccount{} = account, :ok) do
    EmailAccount.record_poll_success(account, DateTime.utc_now(), authorize?: false)
  end

  def run(%EmailAccount{} = account, {:error, _reason}) do
    EmailAccount.record_poll_failure(account, DateTime.utc_now(), authorize?: false)
  end
end
