defmodule ColtWeb.Campaigns.IndexLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    campaigns =
      Campaign.list_for_user!(socket.assigns.current_user.id,
        actor: socket.assigns.current_user,
        load: [:total_count, :done_count]
      )

    {:ok, assign(socket, page_title: gettext("Campaigns"), campaigns: campaigns)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:campaigns}>
      <div class="max-w-[960px] w-full">
        <div class="flex items-end justify-between gap-6 mb-10">
          <Liid.headline
            kicker={gettext("Workspace")}
            sub={gettext("Every search you've started, newest first.")}
          >
            {raw(gettext("Your <em>campaigns</em>."))}
          </Liid.headline>
          <.link navigate={~p"/campaigns/new"} class="no-underline">
            <Liid.btn variant={:primary} mono>
              {gettext("New campaign")} <Liid.icon name="arrow" />
            </Liid.btn>
          </.link>
        </div>

        <div
          :if={@campaigns == []}
          class="border border-border rounded-[11px] bg-card px-8 py-12 text-center [box-shadow:var(--shadow)]"
        >
          <div class="text-[20px] font-semibold tracking-[-0.02em] text-ink">
            {gettext("No campaigns yet.")}
          </div>
          <div class="mt-2 text-[13px] text-inkSoft">
            {gettext("Start by naming the first one.")}
          </div>
          <div class="mt-6 inline-block">
            <.link navigate={~p"/campaigns/new"} class="no-underline">
              <Liid.btn variant={:primary} mono>
                {gettext("New campaign")} <Liid.icon name="arrow" />
              </Liid.btn>
            </.link>
          </div>
        </div>

        <ul :if={@campaigns != []} class="flex flex-col gap-3">
          <%= for c <- @campaigns do %>
            <li>
              <.link
                navigate={destination_for(c)}
                class="flex items-center gap-6 px-5 py-4 no-underline text-ink bg-card border border-border rounded-[11px] [box-shadow:var(--shadow)] hover:bg-paperAlt"
              >
                <div class="flex-1 min-w-0">
                  <div class="text-[17px] font-bold tracking-[-0.01em] truncate">
                    {c.name}
                  </div>
                  <div class="mt-1.5 text-[11.5px] text-inkFaint tracking-[0.02em] flex items-center gap-2.5">
                    <span class="uppercase tracking-[0.08em] font-semibold">{c.status}</span>
                    <span>·</span>
                    <span class="tabular-nums">
                      {gettext("%{done} / %{total} enriched",
                        done: c.done_count,
                        total: c.total_count
                      )}
                    </span>
                    <span>·</span>
                    <span>{relative_time(c.inserted_at)}</span>
                  </div>
                </div>
                <Liid.icon name="chev-r" size={14} class="text-inkFaint shrink-0" />
              </.link>
            </li>
          <% end %>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  defp destination_for(%{status: :draft, id: id}), do: ~p"/campaigns/#{id}/icp"
  defp destination_for(%{status: :collecting, id: id}), do: ~p"/campaigns/#{id}/filters"

  defp destination_for(%{sending_initialized?: true, id: id}),
    do: ~p"/campaigns/#{id}/sending-funnel"

  defp destination_for(%{id: id}), do: ~p"/campaigns/#{id}/funnel"

  defp relative_time(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> gettext("just now")
      diff < 3600 -> gettext("%{n}m ago", n: div(diff, 60))
      diff < 86_400 -> gettext("%{n}h ago", n: div(diff, 3600))
      diff < 7 * 86_400 -> gettext("%{n}d ago", n: div(diff, 86_400))
      true -> gettext("%{n}w ago", n: div(diff, 7 * 86_400))
    end
  end
end
