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

  on_mount {ColtWeb.LiveUserAuth, :live_plan_required}

  @presets [50, 100, 250, 500, 1000]

  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Campaign.get(id, actor: user, load: [:done_count]) do
      {:ok, campaign} ->
        max_target = max_target(campaign, user)
        draft = min(campaign.target_contact_count || 100, max_target || 100)

        {:ok,
         assign(socket,
           page_title: gettext("Target — %{name}", name: campaign.name),
           campaign: campaign,
           max_target: max_target,
           draft: draft,
           saved?: false,
           error: nil
         )}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  # Highest target the owner can set right now: already-enriched contacts plus
  # remaining monthly capacity. `nil` means uncapped (admins). Mirrors
  # `CapacityGuard` so the UI never offers a value the action will reject.
  defp max_target(_campaign, %{is_admin: true}), do: nil

  defp max_target(campaign, user) do
    case Ash.load(user, [:remaining_capacity], authorize?: false) do
      {:ok, %{remaining_capacity: remaining}} when is_integer(remaining) ->
        (campaign.done_count || 0) + max(remaining, 0)

      _ ->
        nil
    end
  end

  def handle_event("confirm", _params, socket) do
    campaign = socket.assigns.campaign
    target = socket.assigns.draft
    user = socket.assigns.current_user

    cond do
      campaign.status in [:draft, :collecting] and cap_reached?(user) ->
        {:noreply, assign(socket, error: start_block_message(user))}

      campaign.status in [:draft, :collecting] ->
        case EnrichmentStart.run(campaign, target, user) do
          {:ok, %{campaign: c}} ->
            {:noreply, push_navigate(socket, to: ~p"/campaigns/#{c.id}/funnel")}

          {:error, err} ->
            {:noreply, assign(socket, error: humanize_error(err))}
        end

      true ->
        with {:ok, c} <- Campaign.update_target(campaign, target, actor: user),
             {:ok, _} <- Topup.schedule(c.id, schedule_in: 0) do
          {:noreply, assign(socket, campaign: c, saved?: true, error: nil)}
        else
          {:error, err} -> {:noreply, assign(socket, error: humanize_error(err))}
        end
    end
  end

  def handle_event("pick", %{"target" => target}, socket) do
    case parse_target(target) do
      nil -> {:noreply, socket}
      n -> {:noreply, assign(socket, draft: clamp(n, socket.assigns.max_target), saved?: false)}
    end
  end

  # Pull a human-readable message out of an Ash error, dropping the internal
  # `over_capacity:` prefix the change tags it with. Falls back to a generic
  # line rather than dumping the whole struct.
  defp humanize_error(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.map_join(" ", &message_for/1)
    |> case do
      "" -> gettext("Something went wrong — please try again.")
      msg -> String.trim_leading(msg, "over_capacity: ")
    end
  end

  defp humanize_error(_), do: gettext("Something went wrong — please try again.")

  defp message_for(%{message: msg}) when is_binary(msg), do: msg
  defp message_for(_), do: ""

  defp clamp(n, nil), do: n
  defp clamp(n, max) when n > max, do: max
  defp clamp(n, _max), do: n

  defp parse_target(n) when is_integer(n) and n > 0, do: n

  defp parse_target(s) when is_binary(s) do
    case Integer.parse(String.replace(s, ~r/[^0-9]/, "")) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_target(_), do: nil

  # Admins bypass; otherwise block a *fresh* start when there's no plan or
  # either monthly cap is spent. This never locks the view — existing data
  # stays fully accessible; only starting new enrichment is gated. Not-loaded
  # calcs don't block — Topup still enforces the hard limit.
  defp cap_reached?(%{is_admin: true}), do: false

  defp cap_reached?(user) do
    reached?(Map.get(user, :remaining_capacity)) or reached?(Map.get(user, :remaining_screening))
  end

  defp reached?(n) when is_integer(n), do: n <= 0
  defp reached?(_), do: false

  defp start_block_message(user) do
    if Colt.Accounts.User.paid?(user) do
      gettext("Monthly limit reached — upgrade your plan or wait for it to renew to start more.")
    else
      gettext("You need an active plan to start enriching — pick one on the pricing page.")
    end
  end

  def render(assigns) do
    presets = Enum.filter(@presets, &(is_nil(assigns.max_target) or &1 <= assigns.max_target))
    # Offer the cap itself when it isn't already one of the presets.
    show_max? = not is_nil(assigns.max_target) and assigns.max_target not in presets
    assigns = assign(assigns, presets: presets, show_max?: show_max?)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      step={5}
      campaign={@campaign}
      campaign_name={@campaign.name}
      campaign_id={@campaign.id}
    >
      <div class="flex flex-col gap-6 max-w-[640px] mx-auto py-12">
        <div class="text-[10.5px] tracking-[0.09em] uppercase text-inkFaint font-semibold">
          {gettext("06 / Target · %{name}", name: @campaign.name)}
        </div>
        <h1 class="font-semibold text-[25px] md:text-[28px] leading-[1.15] tracking-[-0.02em] m-0 text-ink">
          {raw(gettext("How many <em>contacts</em> do you want?"))}
        </h1>
        <p class="text-[14px] leading-[1.5] text-inkSoft max-w-[520px]">
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
                "px-4 py-2 border text-[13px] tnum font-semibold rounded-[8px] cursor-pointer transition-all",
                n == @draft && "border-accentRing bg-accentSoft text-accent",
                n != @draft &&
                  "border-border bg-card text-inkSoft hover:bg-paperAlt hover:text-ink [box-shadow:var(--shadow)]"
              ]}
            >
              {n}
            </button>
          <% end %>
          <button
            :if={@show_max?}
            type="button"
            phx-click="pick"
            phx-value-target={@max_target}
            class={[
              "px-4 py-2 border text-[13px] tnum font-semibold rounded-[8px] cursor-pointer transition-all",
              @max_target == @draft && "border-accentRing bg-accentSoft text-accent",
              @max_target != @draft &&
                "border-border bg-card text-inkSoft hover:bg-paperAlt hover:text-ink [box-shadow:var(--shadow)]"
            ]}
          >
            {gettext("Max · %{n}", n: @max_target)}
          </button>
          <form id="target-form" phx-change="pick" class="inline-flex">
            <input
              type="text"
              id="target-input"
              inputmode="numeric"
              name="target"
              value={@draft}
              phx-debounce="400"
              class="w-[100px] px-3 py-2 border border-border bg-card text-[13px] tnum rounded-[8px] outline-none focus:border-accentRing focus:[box-shadow:inset_0_0_0_1px_var(--accentRing)]"
            />
          </form>
        </div>

        <div class="flex flex-wrap items-center gap-3 mt-4">
          <.link
            navigate={~p"/campaigns/#{@campaign.id}/suppression"}
            class="inline-flex items-center gap-2 px-3.5 py-[7px] text-[12px] font-semibold border border-borderStrong bg-card rounded-[8px] no-underline text-inkSoft hover:bg-paperAlt hover:text-ink [box-shadow:var(--shadow)]"
          >
            <Liid.icon name="chev-l" size={11} /> {gettext("Back to exclude")}
          </.link>
          <Liid.btn variant={:primary} phx-click="confirm">
            {confirm_label(@campaign.status, @draft)}
          </Liid.btn>
          <span :if={@saved?} class="text-[11px] text-inkSoft">{gettext("saved.")}</span>
          <span :if={@error} class="text-[11px] text-red">{@error}</span>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp confirm_label(s, n) when s in [:draft, :collecting],
    do: gettext("Start enrichment · %{n} contacts", n: n)

  defp confirm_label(_, n), do: gettext("Save · %{n} contacts", n: n)
end
