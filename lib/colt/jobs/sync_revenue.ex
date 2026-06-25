defmodule Colt.Jobs.SyncRevenue do
  @moduledoc """
  Cron-driven daily revenue sync. Pulls each Stripe-linked client's paid
  invoices and upserts them as `:subscription` rows in `RevenueEntry` (idempotent
  on the Stripe invoice id), keeping the admin profit view current without a
  manual click.

  Cron wiring lives in `config/config.exs`. Off-Stripe revenue is still entered
  by hand in the admin UI — this job never touches those rows.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 3600, states: [:available, :scheduled, :executing]]

  alias Colt.Services.Billing.RevenueSync

  @impl true
  def perform(_job), do: RevenueSync.run()
end
