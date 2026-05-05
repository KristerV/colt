defmodule ColtWeb.HomeLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    recent =
      Campaign.list_recent_for_user!(socket.assigns.current_user.id,
        actor: socket.assigns.current_user,
        load: [:total_count, :done_count]
      )

    {:ok, assign(socket, page_title: "Home", recent: recent)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-[760px]">
        <Liid.headline
          kicker="00 / Home"
          sub="Start a hunt to pull a candidate list, narrow with filters, and ship a CSV."
        >
          Welcome to <em>Liid</em>.
        </Liid.headline>

        <div class="mt-14 flex items-center gap-4">
          <.link navigate={~p"/campaigns/new"}>
            <Liid.btn variant={:primary} mono>
              New campaign <Liid.icon name="arrow" />
            </Liid.btn>
          </.link>
        </div>

        <div class="mt-20 border-t border-rule pt-6">
          <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink40 mb-4">
            Recent
          </div>
          <div :if={@recent == []} class="text-[13px] text-ink55 italic">
            Nothing here yet.
          </div>
          <div :for={c <- @recent} class="py-2.5 border-b border-rule">
            <.link
              navigate={destination_for(c)}
              class="block no-underline text-ink hover:text-ink"
            >
              <div class="text-[13px] mb-0.5">{c.name}</div>
              <div class="flex justify-between font-mono text-[10px] text-ink40 tracking-[0.04em] tnum">
                <span>{c.done_count} / {c.total_count}</span>
                <span>{relative_time(c.inserted_at)}</span>
              </div>
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp destination_for(%{status: :draft, id: id}), do: ~p"/campaigns/#{id}/icp"
  defp destination_for(%{status: :collecting, id: id}), do: ~p"/campaigns/#{id}/market"
  defp destination_for(%{id: id}), do: ~p"/campaigns/#{id}/icp"

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
