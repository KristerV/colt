defmodule Colt.Jobs.SendDueEmails do
  @moduledoc """
  Cron-driven dispatcher for the send loop. Fires every 60s, pulls up to
  200 outbound Emails whose `scheduled_at <= now`, and enqueues a
  `Colt.Jobs.SendOne` job per row.

  Cron wiring lives in `config/config.exs`. Concurrency for the actual
  sends is bounded by the `:sending` queue (see same file).

  This worker never sends directly — that lives in `SendOne` so retry
  semantics and per-email failure isolation work properly.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 30, states: [:available, :scheduled, :executing]]

  alias Colt.Resources.OutboundEmail

  @impl true
  def perform(_job) do
    now = DateTime.utc_now()

    case OutboundEmail.list_due(now, 200, authorize?: false) do
      {:ok, rows} ->
        Enum.each(rows, fn email -> Colt.Jobs.SendOne.enqueue(email.id) end)
        {:ok, length(rows)}

      rows when is_list(rows) ->
        Enum.each(rows, fn email -> Colt.Jobs.SendOne.enqueue(email.id) end)
        {:ok, length(rows)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
