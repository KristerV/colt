defmodule ColtWeb.Campaigns.NewLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "New campaign", name: "", error: nil)}
  end

  def handle_event("validate", %{"name" => name}, socket) do
    {:noreply, assign(socket, name: name, error: nil)}
  end

  def handle_event("create", %{"name" => name}, socket) do
    name = String.trim(name)

    cond do
      name == "" ->
        {:noreply, assign(socket, error: "Name a campaign before continuing.")}

      true ->
        case Campaign.create_draft(name, actor: socket.assigns.current_user) do
          {:ok, campaign} ->
            {:noreply, push_navigate(socket, to: ~p"/campaigns/#{campaign.id}/icp")}

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
          kicker="01 / Campaign"
          sub="Name it after the persona, market, or quarter — anything you'll recognise in three weeks."
        >
          What are we calling this <em>hunt</em>?
        </Liid.headline>

        <form
          phx-change="validate"
          phx-submit="create"
          class="mt-14"
          autocomplete="off"
        >
          <input
            type="text"
            name="name"
            value={@name}
            placeholder="Nordic CTOs Q2"
            phx-debounce="200"
            autofocus
            class="w-full font-serif text-[28px] md:text-[44px] font-normal tracking-[-0.02em] text-ink py-[12px] pb-[14px] border-0 border-b border-ink bg-transparent outline-none placeholder:text-ink40"
          />

          <div class="mt-3 font-mono text-[11px] tracking-[0.04em] text-ink55">
            <span style="color: var(--color-accent);">●</span> draft · saved on continue
          </div>

          <div :if={@error} class="mt-4 font-mono text-[11px] text-fail">
            {@error}
          </div>

          <div class="mt-16 flex items-center gap-4">
            <Liid.btn variant={:primary} mono type="submit">
              Continue <Liid.icon name="arrow" />
            </Liid.btn>
            <span class="font-mono text-[11px] text-ink40">⏎ to continue</span>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
