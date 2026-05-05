defmodule ColtWeb.Campaigns.NewLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "New campaign", name: "", error: nil)
      |> assign_recent()

    {:ok, socket}
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

  defp assign_recent(socket) do
    recent =
      Campaign.list_recent_for_user!(socket.assigns.current_user.id,
        actor: socket.assigns.current_user,
        load: [:total_count, :done_count]
      )

    assign(socket, recent: recent)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} step={0}>
      <div class="relative flex-1 flex flex-col justify-center max-w-[760px]">
        <Liid.headline
          kicker="01 / Campaign"
          sub="Every search is saved as a campaign. Name it after the persona, market, or quarter — anything you'll recognise in three weeks."
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
            class="w-full max-w-[560px] font-serif text-[44px] font-normal tracking-[-0.02em] text-ink py-[12px] pb-[14px] border-0 border-b border-ink bg-transparent outline-none placeholder:text-ink40"
          />

          <div class="mt-3 font-mono text-[11px] tracking-[0.04em] text-ink55">
            <span style="color: var(--accent);">●</span> draft · saved on continue
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

        <.recent_sidebar recent={@recent} />
      </div>
    </Layouts.app>
    """
  end

  attr :recent, :list, required: true

  defp recent_sidebar(assigns) do
    ~H"""
    <aside class="absolute right-0 top-[120px] w-[240px] border-l border-rule pl-6">
      <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink40 mb-4">
        Recent
      </div>
      <div :if={@recent == []} class="text-[13px] text-ink55 italic">
        Nothing here yet.
      </div>
      <%= for c <- @recent do %>
        <.link
          navigate={~p"/campaigns/#{c.id}/icp"}
          class="block py-2.5 border-b border-rule no-underline text-ink hover:text-ink"
        >
          <div class="text-[13px] mb-0.5 truncate">{c.name}</div>
          <div class="flex justify-between font-mono text-[10px] text-ink40 tracking-[0.04em]">
            <span class="tnum">{c.done_count} / {c.total_count}</span>
            <span>{relative_time(c.inserted_at)}</span>
          </div>
        </.link>
      <% end %>
    </aside>
    """
  end

  defp relative_time(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 7 * 86_400 -> "#{div(diff, 86_400)}d ago"
      true -> "#{div(diff, 7 * 86_400)}w ago"
    end
  end
end
