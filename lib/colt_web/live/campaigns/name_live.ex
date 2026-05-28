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

        <form phx-change="validate" phx-submit="save" class="mt-14" autocomplete="off">
          <input
            type="text"
            name="name"
            value={@name}
            phx-debounce="200"
            autofocus
            class="w-full font-serif text-[28px] md:text-[44px] font-normal tracking-[-0.02em] text-ink py-[12px] pb-[14px] border-0 border-b border-ink bg-transparent outline-none placeholder:text-ink40"
          />

          <div :if={@error} class="mt-4 font-mono text-[11px] text-fail">
            {@error}
          </div>
          <div :if={@saved?} class="mt-4 font-mono text-[11px] text-ink55">
            {gettext("saved.")}
          </div>

          <div class="mt-16">
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
