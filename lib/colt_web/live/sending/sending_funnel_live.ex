defmodule ColtWeb.Sending.SendingFunnelLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        {:ok,
         assign(socket,
           page_title: "Sending funnel — #{campaign.name}",
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
      active={:sending_funnel}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <ColtWeb.Sending.Stubs.coming_soon
        kicker="Sending · Funnel"
        title="Reply funnel, bucket strip, thread split-pane land in phase E8."
        body="Reply rate, interest rate, bounce rate, per-step funnel buckets and the thread split-pane all live here once sending is operational."
      />
    </Layouts.app>
    """
  end
end
