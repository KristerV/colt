defmodule ColtWeb.Campaigns.NewLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("New campaign"), name: "", error: nil)}
  end

  def handle_event("validate", %{"name" => name}, socket) do
    {:noreply, assign(socket, name: name, error: nil)}
  end

  def handle_event("create", %{"name" => name}, socket) do
    name = String.trim(name)

    cond do
      name == "" ->
        {:noreply, assign(socket, error: gettext("Name a campaign before continuing."))}

      true ->
        case Campaign.create_draft(name, actor: socket.assigns.current_user) do
          {:ok, campaign} ->
            {:noreply, push_navigate(socket, to: ~p"/campaigns/#{campaign.id}/market")}

          {:error, _} = err ->
            {:noreply, assign(socket, error: inspect(err))}
        end
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:campaigns}>
      <div class="max-w-[640px] w-full">
        <Liid.headline
          kicker={gettext("01 / Campaign")}
          sub={
            gettext(
              "Name it after the persona, market, or quarter — anything you'll recognise in three weeks."
            )
          }
        >
          {raw(gettext("What are we calling this <em>hunt</em>?"))}
        </Liid.headline>

        <form
          id="campaign-new-form"
          phx-change="validate"
          phx-submit="create"
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
              placeholder={gettext("Nordic CTOs Q2")}
              phx-debounce="200"
              autofocus
              class="w-full text-[20px] font-semibold tracking-[-0.01em] text-ink px-4 py-3 border border-borderStrong bg-card rounded-[8px] outline-none placeholder:text-inkFaint focus:border-accent focus:[box-shadow:0_0_0_3px_var(--accentSoft)]"
            />

            <div class="mt-3 text-[11.5px] tracking-[0.02em] text-inkSoft flex items-center gap-1.5">
              <span class="inline-block w-[7px] h-[7px] rounded-full bg-accent shrink-0" />
              {gettext("draft · saved on continue")}
            </div>

            <div :if={@error} class="mt-3 text-[12px] text-red">
              {@error}
            </div>
          </div>

          <div class="mt-6 flex items-center gap-4">
            <Liid.btn variant={:primary} mono type="submit">
              {gettext("Continue")} <Liid.icon name="arrow" />
            </Liid.btn>
            <span class="text-[11.5px] text-inkFaint">{gettext("⏎ to continue")}</span>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
