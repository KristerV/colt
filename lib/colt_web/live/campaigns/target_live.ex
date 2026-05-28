defmodule ColtWeb.Campaigns.TargetLive do
  @moduledoc """
  View 4 — pick the target contact count. Pre-start this advances the
  campaign to :enriching via `EnrichmentStart`; post-start it just
  updates the target and schedules a Topup so the new number takes effect.
  """
  use ColtWeb, :live_view

  alias Colt.Jobs.Enrichment.Topup
  alias Colt.Resources.Campaign
  alias Colt.Services.Enrichment.Start, as: EnrichmentStart
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  @presets [50, 100, 250, 500, 1000]

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        {:ok,
         assign(socket,
           page_title: gettext("Target — %{name}", name: campaign.name),
           campaign: campaign,
           draft: campaign.target_contact_count || 100,
           saved?: false,
           error: nil
         )}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_event("confirm", _params, socket) do
    campaign = socket.assigns.campaign
    target = socket.assigns.draft

    case campaign.status do
      s when s in [:draft, :collecting] ->
        case EnrichmentStart.run(campaign, target, socket.assigns.current_user) do
          {:ok, %{campaign: c}} ->
            {:noreply, push_navigate(socket, to: ~p"/campaigns/#{c.id}/funnel")}

          {:error, err} ->
            {:noreply, assign(socket, error: inspect(err))}
        end

      _ ->
        with {:ok, c} <-
               Campaign.update_target(campaign, target, actor: socket.assigns.current_user),
             {:ok, _} <- Topup.schedule(c.id, schedule_in: 0) do
          {:noreply, assign(socket, campaign: c, saved?: true, error: nil)}
        else
          {:error, err} -> {:noreply, assign(socket, error: inspect(err))}
        end
    end
  end

  def handle_event("pick", %{"target" => target}, socket) do
    case parse_target(target) do
      nil -> {:noreply, socket}
      n -> {:noreply, assign(socket, draft: n, saved?: false)}
    end
  end

  defp parse_target(n) when is_integer(n) and n > 0, do: n

  defp parse_target(s) when is_binary(s) do
    case Integer.parse(String.replace(s, ~r/[^0-9]/, "")) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_target(_), do: nil

  def render(assigns) do
    assigns = assign(assigns, presets: @presets)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      step={4}
      campaign={@campaign}
      campaign_name={@campaign.name}
      campaign_id={@campaign.id}
    >
      <div class="flex flex-col gap-6 max-w-[640px] mx-auto py-12">
        <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55">
          {gettext("05 / Target · %{name}", name: @campaign.name)}
        </div>
        <h1 class="font-serif font-normal text-[32px] md:text-[44px] leading-none tracking-[-0.02em] m-0">
          {raw(
            gettext(
              "How many <em style=\"font-family: 'Instrument Serif', serif;\">contacts</em> do you want?"
            )
          )}
        </h1>
        <p class="text-[14px] text-ink55 max-w-[520px]">
          {gettext(
            "We'll keep pulling and enriching companies until we hit this number of named contacts (or run out of matches). About 1 in 5 companies yields a contact, so we'll need ~5× this many companies in the funnel."
          )}
        </p>

        <div class="flex flex-wrap gap-2 mt-2">
          <%= for n <- @presets do %>
            <button
              type="button"
              phx-click="pick"
              phx-value-target={n}
              class={[
                "px-4 py-2 border font-mono text-[12px] rounded-sharp cursor-pointer",
                n == @draft && "border-ink bg-ink text-paper",
                n != @draft && "border-ink20 text-ink hover:border-ink"
              ]}
            >
              {n}
            </button>
          <% end %>
          <form phx-change="pick" class="inline-flex">
            <input
              type="text"
              inputmode="numeric"
              name="target"
              value={@draft}
              phx-debounce="400"
              class="w-[100px] px-3 py-2 border border-ink20 bg-paperAlt font-mono text-[12px] rounded-sharp outline-none focus:border-ink"
            />
          </form>
        </div>

        <div class="flex items-center gap-3 mt-4">
          <.link
            navigate={~p"/campaigns/#{@campaign.id}/filters"}
            class="inline-flex items-center gap-2 px-3 py-[7px] text-[12px] border border-ink20 rounded-sharp no-underline text-ink"
          >
            <Liid.icon name="chev-l" size={11} /> {gettext("Back to filters")}
          </.link>
          <Liid.btn variant={:primary} mono phx-click="confirm">
            {confirm_label(@campaign.status, @draft)}
          </Liid.btn>
          <span :if={@saved?} class="font-mono text-[11px] text-ink55">{gettext("saved.")}</span>
          <span :if={@error} class="font-mono text-[11px] text-fail">{@error}</span>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp confirm_label(s, n) when s in [:draft, :collecting],
    do: gettext("Start enrichment · %{n} contacts", n: n)

  defp confirm_label(_, n), do: gettext("Save · %{n} contacts", n: n)
end
