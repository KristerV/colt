defmodule Colt.Services.Enrichment.Start do
  @moduledoc """
  Funnel-time orchestrator. Locks the campaign at `:enriching` with the
  user's chosen `target_contact_count` and kicks off the first
  `Topup` heartbeat. All sampling/job-enqueuing lives in
  `Colt.Services.Enrichment.Topup`.
  """

  alias Colt.Jobs.Enrichment.Topup
  alias Colt.Resources.Campaign
  alias Colt.Services.Discord

  def run(%Campaign{} = campaign, target_contact_count, actor)
      when is_integer(target_contact_count) and target_contact_count > 0 do
    with {:ok, campaign} <- Campaign.finalize(campaign, target_contact_count, actor: actor),
         {:ok, _job} <- Topup.schedule(campaign.id, schedule_in: 0),
         {:ok, _} <- maybe_notify(campaign, actor) do
      {:ok, %{campaign: campaign}}
    end
  end

  defp maybe_notify(campaign, %{is_admin: false} = actor) do
    url = ColtWeb.Endpoint.url() <> "/campaigns/#{campaign.id}/funnel"
    Discord.Notify.run("New search by #{actor.email}: #{url}")
  end

  defp maybe_notify(_campaign, _actor), do: {:ok, :skipped}
end
