defmodule ColtWeb.Components.AutoApproveToggle do
  @moduledoc """
  Sidebar toggle for campaign auto-approve, in the Sending section header.
  Labelled AUTO. Locked (greyed) until the campaign has at least one
  committed contact — i.e. a variant has been seeded — so it can't be turned
  on before there's anything to auto-send. Flipping it on asks for a confirm
  (it sends without review); off is instant.
  """

  use ColtWeb, :live_component

  alias Colt.Resources.{Campaign, CampaignContact}

  @impl true
  def update(%{campaign: campaign, current_user: user}, socket) do
    {:ok,
     assign(socket,
       campaign: campaign,
       current_user: user,
       on: campaign.auto_approve_on?,
       unlocked?: unlocked?(campaign.id, user)
     )}
  end

  defp unlocked?(campaign_id, user) do
    case CampaignContact.any_committed_for_campaign(campaign_id, actor: user) do
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end

  @impl true
  def handle_event("toggle", _params, %{assigns: %{unlocked?: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("toggle", _params, socket) do
    new_value = !socket.assigns.on

    case Campaign.set_auto_approve_on(socket.assigns.campaign, new_value,
           actor: socket.assigns.current_user
         ) do
      {:ok, updated} ->
        {:noreply, assign(socket, on: updated.auto_approve_on?, campaign: updated)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle"
      phx-target={@myself}
      disabled={not @unlocked?}
      data-confirm={
        if @unlocked? and not @on,
          do:
            "Turn on auto-approve? New contacts will be written and sent without your review. You can turn it off anytime."
      }
      title={tooltip(@unlocked?, @on)}
      class={[
        "inline-flex items-center gap-1.5 border-0 p-0 bg-transparent",
        if(@unlocked?, do: "cursor-pointer", else: "cursor-not-allowed opacity-45")
      ]}
    >
      <span class="font-mono text-[9px] tracking-[0.14em] uppercase text-ink40">auto</span>
      <span class="relative inline-block w-6 h-[13px] rounded-full">
        <span
          class="absolute inset-0 rounded-full"
          style={"background: #{if @on, do: "var(--color-accent)", else: "var(--color-ink20)"}; transition: background .12s;"}
        />
        <span
          class="absolute top-px w-[11px] h-[11px] rounded-full bg-paper"
          style={"left: #{if @on, do: "12px", else: "1px"}; box-shadow: 0 1px 2px rgba(0,0,0,0.2); transition: left .12s;"}
        />
      </span>
    </button>
    """
  end

  defp tooltip(false, _),
    do:
      gettext(
        "Auto-approve — locked. Approve a few contacts first; then new contacts get written and sent automatically."
      )

  defp tooltip(true, true),
    do:
      gettext(
        "Auto-approve is ON — new contacts are written and sent automatically. Click to turn off."
      )

  defp tooltip(true, false),
    do:
      gettext(
        "Auto-approve is OFF — click to let new contacts be written and sent without review."
      )
end
