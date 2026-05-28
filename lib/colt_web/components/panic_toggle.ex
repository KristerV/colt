defmodule ColtWeb.Components.PanicToggle do
  @moduledoc """
  Stateful sidebar toggle for the campaign-level panic switch. Lives
  inside the Sending section header. Clicking it flips
  `Campaign.panic_switch_on`, then broadcasts on the campaign PubSub
  topic so parent LiveViews refresh the banner state.
  """

  use ColtWeb, :live_component

  alias Colt.Resources.Campaign

  @impl true
  def render(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle"
      phx-target={@myself}
      title={
        if @on,
          do: gettext("Sending paused — click to resume"),
          else: gettext("Sending on — click to pause")
      }
      class="relative inline-block w-6 h-[13px] rounded-full border-0 p-0 cursor-pointer bg-transparent"
    >
      <span
        class="absolute inset-0 rounded-full"
        style={"background: #{if @on, do: "var(--color-ink20)", else: "var(--color-accent)"}; transition: background .12s;"}
      />
      <span
        class="absolute top-px w-[11px] h-[11px] rounded-full bg-paper"
        style={"left: #{if @on, do: "1px", else: "12px"}; box-shadow: 0 1px 2px rgba(0,0,0,0.2); transition: left .12s;"}
      />
    </button>
    """
  end

  @impl true
  def update(%{campaign: campaign, current_user: user}, socket) do
    {:ok,
     assign(socket,
       campaign_id: campaign.id,
       on: campaign.panic_switch_on,
       campaign: campaign,
       current_user: user
     )}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    actor = socket.assigns.current_user
    campaign = socket.assigns.campaign
    new_value = !campaign.panic_switch_on

    case Campaign.set_panic(campaign, new_value, actor: actor) do
      {:ok, updated} ->
        # LiveComponents share the parent LV's process, so a plain send/2
        # is enough to let the parent refresh its campaign assign (which
        # the screen banner reads).
        send(self(), {:panic_toggled, updated})

        {:noreply, assign(socket, on: updated.panic_switch_on, campaign: updated)}

      {:error, _} ->
        {:noreply, socket}
    end
  end
end
