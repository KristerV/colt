defmodule ColtWeb.Sending.SequenceLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        {:ok,
         assign(socket,
           page_title: "Sequence — #{campaign.name}",
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
      active={:sequence}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <ColtWeb.Sending.Stubs.coming_soon
        kicker="Sending · Sequence"
        title="Sequence editor lands in phase E2."
        body="Design the multi-step outreach plan for this campaign — initial email, followups with day-delays, terminal action. Until E2 ships, this view is a placeholder."
      />
    </Layouts.app>
    """
  end
end
