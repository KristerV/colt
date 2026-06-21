defmodule ColtWeb.Campaigns.MarketLive do
  use ColtWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias Colt.Markets
  alias Colt.Resources.{AnnualReport, Campaign, Company}
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        socket =
          socket
          |> assign(
            page_title: gettext("Market — %{name}", name: campaign.name),
            campaign: campaign,
            selected: campaign.market || :ee,
            markets: Markets.all(),
            counts: active_counts(),
            ee_count: ee_active_count(),
            last_sync: last_sync_at(),
            next_done?: filters_present?(campaign),
            saved?: false,
            error: nil
          )

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/campaigns/new")}
    end
  end

  def handle_event("select", %{"market" => market}, socket) do
    enabled = Markets.enabled_atoms() |> Enum.map(&Atom.to_string/1)

    if market in enabled do
      {:noreply, assign(socket, selected: String.to_existing_atom(market))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("continue", _params, socket) do
    case Campaign.set_market(socket.assigns.campaign, socket.assigns.selected,
           actor: socket.assigns.current_user
         ) do
      {:ok, campaign} ->
        if socket.assigns.next_done? do
          {:noreply, assign(socket, campaign: campaign, saved?: true, error: nil)}
        else
          {:noreply, push_navigate(socket, to: ~p"/campaigns/#{campaign.id}/filters")}
        end

      {:error, err} ->
        {:noreply, assign(socket, error: inspect(err))}
    end
  end

  defp filters_present?(%{filters: f}) when is_map(f), do: map_size(f) > 0
  defp filters_present?(_), do: false

  defp ee_active_count do
    Colt.Repo.aggregate(
      from(c in Company, where: c.market == :ee and c.status == :registered),
      :count,
      :id
    )
  end

  defp active_counts do
    from(c in Company,
      where: c.status == :registered,
      group_by: c.market,
      select: {c.market, count(c.id)}
    )
    |> Colt.Repo.all()
    |> Map.new()
  end

  defp last_sync_at do
    Colt.Repo.aggregate(from(r in AnnualReport, []), :max, :updated_at)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      step={2}
      campaign={@campaign}
      campaign_name={@campaign.name}
      campaign_id={@campaign.id}
    >
      <div class="flex flex-col flex-1 min-h-0 gap-6">
        <Liid.headline
          kicker={gettext("02 / Market")}
          sub={
            gettext(
              "One market per campaign. Liid hits the government registry and walks the resulting domain list. Greyed-out registries are scheduled for next quarter."
            )
          }
        >
          {raw(gettext("Which <em>register</em> do we pull from?"))}
        </Liid.headline>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3.5">
          <%= for m <- @markets do %>
            <.market_card
              market={m}
              selected={@selected == m.market}
              count={
                case Map.get(@counts, m.market) do
                  nil -> "—"
                  n -> format_int(n)
                end
              }
            />
          <% end %>
        </div>

        <div :if={@error} class="text-[12px] text-red">{@error}</div>

        <div class="flex-1" />

        <div class="flex flex-wrap items-center gap-4">
          <.link
            navigate={~p"/campaigns/#{@campaign.id}/name"}
            class="inline-flex items-center gap-2 px-4 py-[7px] text-[12px] font-semibold text-inkSoft bg-card border border-borderStrong rounded-[8px] no-underline [box-shadow:var(--shadow)] hover:bg-paperAlt hover:text-ink"
          >
            <Liid.icon name="chev-l" size={11} /> Back
          </.link>
          <Liid.btn variant={:primary} mono phx-click="continue">
            <%= if @next_done? do %>
              {gettext("Save")} <Liid.icon name="check" />
            <% else %>
              {gettext("Continue → filters")} <Liid.icon name="arrow" />
            <% end %>
          </Liid.btn>
          <span :if={@saved?} class="text-[11.5px] text-inkFaint">{gettext("saved.")}</span>
          <span class="w-full md:w-auto md:ml-auto text-[11.5px] text-inkFaint tabular-nums">
            {gettext("%{count} active companies in rik.ee · last sync %{sync}",
              count: format_int(@ee_count),
              sync: format_sync(@last_sync)
            )}
          </span>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :market, :map, required: true
  attr :selected, :boolean, required: true
  attr :count, :string, required: true

  defp market_card(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="select"
      phx-value-market={Atom.to_string(@market.market)}
      disabled={not @market.enabled}
      class={[
        "flex flex-col justify-between p-4 border rounded-[11px] min-h-[128px] text-left [box-shadow:var(--shadow)]",
        not @market.enabled && "opacity-45 cursor-not-allowed",
        @market.enabled && "cursor-pointer",
        @selected &&
          "border-accentRing bg-accentSoft [box-shadow:0_0_0_1px_var(--accentRing),var(--shadow-card)]",
        not @selected && "border-border bg-card hover:bg-paperAlt"
      ]}
    >
      <div class="flex items-start justify-between">
        <div class="flex items-center gap-3">
          <span class={[
            "w-3.5 h-3.5 rounded-full border flex items-center justify-center shrink-0",
            @selected && "border-accent",
            not @selected && "border-inkFaint"
          ]}>
            <span
              :if={@selected}
              class="w-[7px] h-[7px] rounded-full bg-accent"
            />
          </span>
          <span class={[
            "text-[11px] tracking-[0.1em] uppercase font-semibold",
            @selected && "text-accent",
            not @selected && "text-inkFaint"
          ]}>
            {@market.code}
          </span>
        </div>
        <span
          :if={not @market.enabled}
          class="text-[9px] tracking-[0.1em] uppercase text-inkFaint font-semibold bg-paperAlt rounded-[8px] px-2 py-0.5"
        >
          {gettext("soon")}
        </span>
      </div>

      <div class="mt-3">
        <div class={[
          "text-[20px] font-bold tracking-[-0.01em] leading-tight",
          @selected && "text-accent",
          not @selected && "text-ink"
        ]}>
          {@market.name}
        </div>
        <div class="mt-2.5 flex justify-end text-[11.5px] text-inkSoft tabular-nums">
          <span class="text-ink font-semibold">{@count}</span>
        </div>
      </div>
    </button>
    """
  end

  defp format_int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.codepoints()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_int(_), do: "—"

  defp format_sync(nil), do: gettext("never")

  defp format_sync(%DateTime{} = dt) do
    # EET is UTC+2 (we ignore DST/EEST for v1; this is footer aesthetics).
    dt
    |> DateTime.add(2 * 3600, :second)
    |> Calendar.strftime("%H:%M EET")
  end
end
