defmodule ColtWeb.Admin.CampaignsLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign
  alias ColtWeb.Admin.Summary

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  def mount(_params, _session, socket) do
    campaigns =
      Campaign.list_all_recent!(
        actor: socket.assigns.current_user,
        load: [:owner, :total_count, :done_count, :cost_usd]
      )

    {:ok, assign(socket, page_title: "Admin · Campaigns", campaigns: campaigns)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />
        <div>
          <h1 class="text-3xl font-semibold">Campaigns</h1>
          <div class="font-mono text-[11px] text-ink55 mt-1">
            {length(@campaigns)} most recent across all users
          </div>
        </div>

        <div class="border border-rule rounded-sharp overflow-hidden">
          <div class="hidden md:grid md:grid-cols-[2fr_1.5fr_100px_100px_110px_110px_130px] items-center gap-3 px-4 py-2.5 border-b border-rule bg-paperAlt font-mono text-[10px] tracking-[0.12em] uppercase text-ink55">
            <span>Name</span>
            <span>Owner</span>
            <span class="text-right">Done</span>
            <span class="text-right">Total</span>
            <span class="text-right">Cost</span>
            <span>Status</span>
            <span>Created</span>
          </div>

          <%= for c <- @campaigns do %>
            <.link
              navigate={~p"/campaigns/#{c.id}/funnel"}
              class="grid grid-cols-2 md:grid-cols-[2fr_1.5fr_100px_100px_110px_110px_130px] items-center gap-2 md:gap-3 px-4 py-3 border-b border-rule last:border-b-0 hover:bg-paperAlt no-underline text-ink"
            >
              <span class="text-[13px] font-medium truncate">{c.name}</span>
              <span class="text-[12px] text-ink55 truncate">{owner_email(c.owner)}</span>
              <span class="font-mono text-[11px] tnum text-right">{c.done_count}</span>
              <span class="font-mono text-[11px] tnum text-right">{c.total_count}</span>
              <span class="font-mono text-[11px] tnum text-right">{fmt_cost(c.cost_usd)}</span>
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

  defp fmt_cost(nil), do: "—"

  defp fmt_cost(%Decimal{} = d) do
    "$" <> (d |> Decimal.round(4) |> Decimal.to_string(:normal))
  end

  defp fmt_cost(n) when is_number(n), do: "$" <> :erlang.float_to_binary(n / 1, decimals: 4)
end
