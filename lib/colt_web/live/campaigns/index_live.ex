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

    {:ok, assign(socket, page_title: "Campaigns", campaigns: campaigns)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:campaigns}>
      <div class="max-w-[960px] w-full">
        <div class="flex items-end justify-between gap-6 mb-10">
          <Liid.headline kicker="Workspace" sub="Every search you've started, newest first.">
            Your <em>campaigns</em>.
          </Liid.headline>
          <.link navigate={~p"/campaigns/new"} class="no-underline">
            <Liid.btn variant={:primary} mono>
              New campaign <Liid.icon name="arrow" />
            </Liid.btn>
          </.link>
        </div>

        <div
          :if={@campaigns == []}
          class="border border-rule rounded-[2px] bg-paper px-8 py-12 text-center"
        >
          <div class="font-serif text-[24px] tracking-[-0.02em] text-ink">
            No campaigns yet.
          </div>
          <div class="mt-2 text-[13px] text-ink55">
            Start by naming the first one.
          </div>
          <div class="mt-6 inline-block">
            <.link navigate={~p"/campaigns/new"} class="no-underline">
              <Liid.btn variant={:primary} mono>
                New campaign <Liid.icon name="arrow" />
              </Liid.btn>
            </.link>
          </div>
        </div>

        <ul :if={@campaigns != []} class="border-t border-rule">
          <%= for c <- @campaigns do %>
            <li class="border-b border-rule">
              <.link
                navigate={destination_for(c)}
                class="flex items-center gap-6 py-4 no-underline text-ink hover:bg-paperAlt px-2"
              >
                <div class="flex-1 min-w-0">
                  <div class="font-serif text-[22px] tracking-[-0.015em] truncate">
                    {c.name}
                  </div>
                  <div class="mt-1 font-mono text-[11px] text-ink40 tracking-[0.04em] flex items-center gap-3">
                    <span class="uppercase">{c.status}</span>
                    <span>·</span>
                    <span class="tnum">{c.done_count} / {c.total_count} enriched</span>
                    <span>·</span>
                    <span>{relative_time(c.inserted_at)}</span>
                  </div>
                </div>
                <Liid.icon name="chev-r" size={14} class="text-ink40 shrink-0" />
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
  defp destination_for(%{id: id}), do: ~p"/campaigns/#{id}/funnel"

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
