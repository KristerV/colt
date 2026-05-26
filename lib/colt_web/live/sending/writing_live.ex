defmodule ColtWeb.Sending.WritingLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        {:ok,
         assign(socket,
           page_title: "Writing — #{campaign.name}",
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
      active={:writing}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <ColtWeb.Sending.Stubs.coming_soon
        kicker="Sending · Writing"
        title="Per-contact AI-drafted approval queue lands in phase E4."
        body="Reviews each enriched contact's full sequence one at a time. AI drafts subject + body per step; you edit, hit Approve, the next contact loads."
      />
    </Layouts.app>
    """
  end
end
