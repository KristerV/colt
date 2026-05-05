defmodule ColtWeb.Campaigns.FunnelLive do
  @moduledoc """
  Placeholder for view 4. Phase 5 builds the real funnel UI; for Phase 3 we
  just confirm the campaign moved into `:enriching` and let the stub run.
  """
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        {:ok,
         assign(socket,
           page_title: "Funnel — #{campaign.name}",
           campaign: campaign
         )}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      step={4}
      campaign_name={@campaign.name}
      campaign_id={@campaign.id}
    >
      <Liid.headline kicker={"05 / Funnel · #{@campaign.name}"} sub="View 4 ships in Phase 5.">
        Enrichment <em>running</em>.
      </Liid.headline>

      <div class="mt-10 font-mono text-[11px] text-ink55">
        status: {@campaign.status} · finalized_at: {@campaign.finalized_at || "—"}
      </div>
    </Layouts.app>
    """
  end
end
