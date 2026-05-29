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
      <div class="flex flex-col flex-1 min-h-0 gap-10">
        <Liid.headline
          kicker={gettext("03 / Market")}
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

        <div :if={@error} class="font-mono text-[11px] text-fail">{@error}</div>

        <div class="flex-1" />

        <div class="flex flex-wrap items-center gap-4">
          <.link
            navigate={~p"/campaigns/#{@campaign.id}/icp"}
            class="inline-flex items-center gap-2 px-4 py-[7px] text-[12px] border border-ink20 rounded-sharp no-underline text-ink"
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
          <span :if={@saved?} class="font-mono text-[11px] text-ink55">{gettext("saved.")}</span>
          <span class="w-full md:w-auto md:ml-auto font-mono text-[11px] text-ink40">
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
        "flex flex-col justify-between p-6 pb-5 border rounded-sharp min-h-[200px] text-left",
        not @market.enabled && "opacity-45 cursor-not-allowed",
        @market.enabled && "cursor-pointer",
        @selected && "border-ink bg-paperAlt",
        not @selected && "border-ink20 bg-paper"
      ]}
    >
      <div class="flex items-start justify-between">
        <div class="flex items-center gap-3">
          <span class={[
            "w-3.5 h-3.5 rounded-full border flex items-center justify-center shrink-0",
            @selected && "border-[var(--accent)]",
            not @selected && "border-ink40"
          ]}>
            <span
              :if={@selected}
              class="w-[7px] h-[7px] rounded-full"
              style="background: var(--accent);"
            />
          </span>
          <span class="font-mono text-[11px] text-ink55 tracking-[0.12em]">
            {@market.code}
          </span>
        </div>
        <span
          :if={not @market.enabled}
          class="font-mono text-[9px] tracking-[0.12em] uppercase text-ink40 border border-ink20 rounded-sharp px-1.5 py-0.5"
        >
          {gettext("soon")}
        </span>
      </div>

      <div class="mt-5">
        <div class="font-serif text-[38px] font-normal tracking-[-0.02em] leading-none text-ink">
          {@market.name}
        </div>
        <div class="mt-3.5 flex justify-between font-mono text-[11px] text-ink55 tracking-[0.04em]">
          <span>{@market.api}</span>
          <span class="text-ink70">{@count}</span>
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
