defmodule ColtWeb.Admin.CampaignsLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  def mount(_params, _session, socket) do
    campaigns =
      Campaign.list_all_recent!(
        actor: socket.assigns.current_user,
        load: [:owner, :total_count, :done_count]
      )

    {:ok, assign(socket, page_title: "Admin · Campaigns", campaigns: campaigns)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <div>
          <.link navigate="/admin" class="text-sm opacity-60 hover:opacity-100">&larr; Admin</.link>
          <h1 class="text-3xl font-semibold mt-1">Campaigns</h1>
          <div class="font-mono text-[11px] text-ink55 mt-1">
            {length(@campaigns)} most recent across all users
          </div>
        </div>

        <div class="border border-rule rounded-sharp overflow-hidden">
          <div
            class="hidden md:grid items-center gap-3 px-4 py-2.5 border-b border-rule bg-paperAlt font-mono text-[10px] tracking-[0.12em] uppercase text-ink55"
            style="grid-template-columns: 2fr 1.5fr 100px 100px 110px 130px;"
          >
            <span>Name</span>
            <span>Owner</span>
            <span class="text-right">Done</span>
            <span class="text-right">Total</span>
            <span>Status</span>
            <span>Created</span>
          </div>

          <%= for c <- @campaigns do %>
            <.link
              navigate={~p"/campaigns/#{c.id}/funnel"}
              class="grid grid-cols-2 md:grid-cols-none items-center gap-2 md:gap-3 px-4 py-3 border-b border-rule last:border-b-0 hover:bg-paperAlt no-underline text-ink"
              style="grid-template-columns: 2fr 1.5fr 100px 100px 110px 130px;"
            >
              <span class="text-[13px] font-medium truncate">{c.name}</span>
              <span class="text-[12px] text-ink55 truncate">{owner_email(c.owner)}</span>
              <span class="font-mono text-[11px] tnum text-right">{c.done_count}</span>
              <span class="font-mono text-[11px] tnum text-right">{c.total_count}</span>
              <span class="font-mono text-[10px] uppercase tracking-[0.08em] text-ink55">
                {c.status}
              </span>
              <span class="font-mono text-[10px] text-ink55">{fmt_dt(c.inserted_at)}</span>
            </.link>
          <% end %>

          <div :if={@campaigns == []} class="px-4 py-8 text-center font-mono text-[12px] text-ink40">
            no campaigns yet
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp owner_email(%{email: e}), do: to_string(e)
  defp owner_email(_), do: "—"

  defp fmt_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp fmt_dt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp fmt_dt(_), do: "—"
end
