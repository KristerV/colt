defmodule Colt.Services.Sending.AlertPollFailing do
  @moduledoc """
  Discord-alert when an inbox's inbound poll has been failing long enough to
  matter. Fires once on crossing `@first_alert_at` (5 straight minutes, since
  the poller runs every minute), then again every `@repeat_every` failures
  so a stuck mailbox doesn't go quiet after the first ping but also doesn't
  spam once-a-minute forever.
  """

  alias Colt.Resources.EmailAccount
  alias Colt.Services.Discord.Notify

  @first_alert_at 5
  @repeat_every 60

  def run(%EmailAccount{poll_failure_count: n} = account) when n == @first_alert_at do
    notify(account, n)
  end

  def run(%EmailAccount{poll_failure_count: n} = account)
      when n > @first_alert_at and rem(n - @first_alert_at, @repeat_every) == 0 do
    notify(account, n)
  end

  def run(%EmailAccount{}), do: {:ok, :skipped}

  defp notify(account, n) do
    Notify.run(
      "inbound polling has failed #{n}x in a row for #{account.address} " <>
        "(email_account #{account.id}) — replies may be silently missed"
    )

    {:ok, :alerted}
  end
end
