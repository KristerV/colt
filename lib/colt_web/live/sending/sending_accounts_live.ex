defmodule ColtWeb.Sending.SendingAccountsLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        {:ok,
         assign(socket,
           page_title: "Sending accounts — #{campaign.name}",
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
      active={:sending_accounts}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <ColtWeb.Sending.Stubs.coming_soon
        kicker="Sending · Sending accounts"
        title="Per-campaign inbox picker lands in phase E2."
        body="Pick from your connected inboxes and set per-account daily quotas. Capacity readout shows ~N/day for the current selection."
      />
    </Layouts.app>
    """
  end
end
