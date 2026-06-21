defmodule ColtWeb.Campaigns.NameLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        {:ok,
         assign(socket,
           page_title: gettext("Name — %{name}", name: campaign.name),
           campaign: campaign,
           name: campaign.name,
           error: nil,
           saved?: false
         )}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/campaigns")}
    end
  end

  def handle_event("validate", %{"name" => name}, socket) do
    {:noreply, assign(socket, name: name, error: nil, saved?: false)}
  end

  def handle_event("save", %{"name" => name}, socket) do
    name = String.trim(name)

    cond do
      name == "" ->
        {:noreply, assign(socket, error: gettext("Campaign name can't be empty."))}

      name == socket.assigns.campaign.name ->
        {:noreply, assign(socket, saved?: true)}

      true ->
        case Campaign.rename(socket.assigns.campaign, name, actor: socket.assigns.current_user) do
          {:ok, campaign} ->
            {:noreply, assign(socket, campaign: campaign, name: campaign.name, saved?: true)}

          {:error, err} ->
            {:noreply, assign(socket, error: inspect(err))}
        end
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:name}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="max-w-[640px] w-full">
        <Liid.headline
          kicker={gettext("Campaign · Name")}
          sub={gettext("Rename it. Stored immediately on save.")}
        >
          {raw(gettext("The <em>name</em> of this campaign."))}
        </Liid.headline>

        <form
          id="campaign-name-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-10"
          autocomplete="off"
        >
          <div class="bg-card border border-border rounded-[11px] p-6 [box-shadow:var(--shadow)]">
            <label
              for="campaign-name-input"
              class="block text-[10.5px] tracking-[0.08em] uppercase text-inkFaint font-semibold mb-2"
            >
              {gettext("Campaign name")}
            </label>
            <input
              type="text"
              id="campaign-name-input"
              name="name"
              value={@name}
              phx-debounce="200"
              autofocus
              class="w-full text-[20px] font-semibold tracking-[-0.01em] text-ink px-4 py-3 border border-borderStrong bg-card rounded-[8px] outline-none placeholder:text-inkFaint focus:border-accent focus:[box-shadow:0_0_0_3px_var(--accentSoft)]"
            />

            <div :if={@error} class="mt-3 text-[12px] text-red">
              {@error}
            </div>
            <div :if={@saved?} class="mt-3 text-[12px] text-inkFaint">
              {gettext("saved.")}
            </div>
          </div>

          <div class="mt-6">
            <Liid.btn variant={:primary} mono type="submit">
              {gettext("Save")} <Liid.icon name="check" />
            </Liid.btn>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
