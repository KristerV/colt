defmodule Colt.Jobs.AutoApproveDue do
  @moduledoc """
  Hourly cron that drives auto-approve. Light by design: it just finds every
  campaign with auto-approve on (and not panicked) and enqueues one
  `Colt.Jobs.AutoApproveCampaign` job each. All the real work — slot gating,
  drafting, scheduling — happens in that per-campaign job.

  Hourly is enough: each run fills any inbox slots that have freed up since the
  last tick. Flipping the toggle on enqueues the per-campaign job directly
  (see SettingsLive) so the schedule fills immediately, without waiting for the
  next hour.

  Cron wiring lives in `config/config.exs`.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 30, states: [:available, :scheduled, :executing]]

  alias Colt.Resources.Campaign
  alias Colt.Jobs.AutoApproveCampaign

  @impl true
  def perform(_job) do
    campaigns = Campaign.list_auto_approve_active!(authorize?: false)
    Enum.each(campaigns, &AutoApproveCampaign.enqueue(&1.id))
    {:ok, length(campaigns)}
  end
end
