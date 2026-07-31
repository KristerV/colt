defmodule ColtWeb.DeckLive do
  @moduledoc """
  `/demo` — the narrated demo deck prospects watch.

  Which slides play comes from `ColtWeb.Deck.Slides.order/1` keyed on the
  visitor's `ab_funnel` variant, so the short and long decks are the same test
  as whatever the onboarding branches on later.

  Playback is a single `<video>` element that never leaves the DOM: the Play
  button on the cover starts it inside the user's click, which is what buys us
  autoplay permission for every subsequent slide. Advancing is driven by the
  clip's `ended` event, so a slide is exactly as long as its narration. Slides
  with no recording yet fall back to a fixed dwell so the deck is watchable
  before anything has been recorded.
  """
  use ColtWeb, :live_view

  alias Colt.Deck.Manifest
  alias Colt.Markets
  alias Colt.Resources.Company
  alias ColtWeb.Deck.Slides

  # How long an un-narrated slide stays up.
  @fallback_ms 11_000

  # `/demo` plays whatever variant ab_funnel assigned this visitor. `/demo/long`
  # and `/demo/short` pin one, so a specific cut can be linked to directly
  # without disturbing the test.
  def mount(params, _session, socket) do
    variant = pinned_variant(params) || socket.assigns[:ab_funnel_variant]
    keys = Slides.order(variant)
    countries = landing_countries()

    {:ok,
     assign(socket,
       page_title: "Liid — a two-minute demo",
       variant: variant,
       keys: keys,
       index: 0,
       takes: Manifest.read(),
       started?: false,
       finished?: false,
       paused?: false,
       fallback_ms: @fallback_ms,
       tracked: MapSet.new(),
       countries: countries,
       registry_total: registry_total(countries)
     )}
  end

  ## ---------- events ----------

  def handle_event("start", _params, socket) do
    AbFunnel.track(socket, "deck_started", %{variant: socket.assigns.variant})

    {:noreply, socket |> assign(started?: true) |> track_current_slide()}
  end

  # "Paused" means the deck stops moving on by itself — the clip on the current
  # slide still plays to the end. Advancing is the only thing it gates, which is
  # why the decision lives here rather than in the player.
  def handle_event("advance", _params, socket) do
    last = length(socket.assigns.keys) - 1

    cond do
      socket.assigns.paused? ->
        {:noreply, socket}

      socket.assigns.index >= last ->
        AbFunnel.track(socket, "deck_completed")
        {:noreply, assign(socket, finished?: true, paused?: true)}

      true ->
        {:noreply, socket |> assign(index: socket.assigns.index + 1) |> track_current_slide()}
    end
  end

  # Stepping through by hand is a deliberate act — stop auto-advancing so the
  # deck doesn't yank the viewer off the slide they just chose.
  def handle_event("goto", %{"index" => index}, socket) do
    index = index |> to_string() |> String.to_integer()
    index = index |> max(0) |> min(length(socket.assigns.keys) - 1)

    {:noreply,
     socket
     |> assign(index: index, finished?: false, started?: true, paused?: true)
     |> track_current_slide()}
  end

  def handle_event("prev", _params, socket) do
    handle_event("goto", %{"index" => socket.assigns.index - 1}, socket)
  end

  def handle_event("next", _params, socket) do
    handle_event("goto", %{"index" => socket.assigns.index + 1}, socket)
  end

  def handle_event("toggle_pause", _params, socket) do
    {:noreply, assign(socket, paused?: !socket.assigns.paused?)}
  end

  def handle_event("cta", _params, socket) do
    AbFunnel.track(socket, "cta_clicked", %{slide: to_string(current_key(socket.assigns))})

    {:noreply, push_navigate(socket, to: cta_path(socket.assigns[:current_user]))}
  end

  # One event per slide, first view only — scrubbing back must not double-count,
  # or the drop-off funnel in AbFunnel.AdminLive stops meaning anything.
  defp track_current_slide(socket) do
    key = current_key(socket.assigns)

    if MapSet.member?(socket.assigns.tracked, key) do
      socket
    else
      AbFunnel.track(socket, "slide_#{key}")
      assign(socket, tracked: MapSet.put(socket.assigns.tracked, key))
    end
  end

  ## ---------- render ----------

  def render(assigns) do
    ~H"""
    <Slides.styles />

    <div class="deck-fullscreen fixed inset-0 bg-canvas text-ink antialiased flex items-center justify-center">
      <div class="deck-stage" id="deck-stage">
        <Slides.slide
          key={current_key(assigns)}
          registry_total={@registry_total}
          countries={@countries}
        />

        <video
          id="deck-video"
          class="deck-bubble"
          hidden={is_nil(current_take(assigns))}
          phx-hook="DeckPlayer"
          playsinline
          data-src={media_url(current_take(assigns))}
          data-index={@index}
          data-started={to_string(@started? and not @finished?)}
          data-fallback-ms={@fallback_ms}
          data-next-src={next_media_url(assigns)}
        />

        <div :if={!@started?} class="absolute inset-0 z-10 grid place-items-center bg-card">
          <div class="text-center px-8">
            <div class="d-kicker text-accent">Liid · demo</div>
            <h1 class="d-h1 mt-[1.4cqw] max-w-[70cqw] mx-auto">
              Two minutes on how you get <em>booked calls</em>.
            </h1>
            <p class="d-lead text-inkSoft mt-[1.6cqw] max-w-[52cqw] mx-auto">
              Recorded walkthrough. It plays itself — pause any time.
            </p>
            <button
              type="button"
              id="deck-start"
              phx-click="start"
              class="d-btn mt-[3cqw] mx-auto"
            >
              ▶ Play the demo
            </button>
            <div class="d-fine text-inkFaint mt-[1.4cqw]">
              {length(@keys)} slides · about {estimated_minutes(assigns)} min
            </div>
          </div>
        </div>

        <div
          :if={@finished?}
          class="absolute inset-0 z-10 grid place-items-center"
          style="background:rgba(255,255,255,.94);"
        >
          <div class="text-center px-8">
            <h2 class="d-h2">That's the <em>whole</em> thing.</h2>
            <p class="d-lead text-inkSoft mt-[1.4cqw] max-w-[48cqw] mx-auto">
              The first thing it asks you is one sentence about who you sell to.
            </p>
            <div class="flex items-center justify-center gap-[1.2cqw] mt-[2.6cqw]">
              <button type="button" phx-click="cta" class="d-btn">Start a campaign →</button>
              <button
                type="button"
                phx-click="goto"
                phx-value-index="0"
                class="d-btn"
                style="background:var(--card);color:var(--inkSoft);border:1px solid var(--borderStrong);box-shadow:none;"
              >
                Watch again
              </button>
            </div>
          </div>
        </div>

        <div
          :if={@started? && !@finished?}
          class="absolute left-1/2 -translate-x-1/2 bottom-[2cqw] z-[4] flex items-center gap-2 rounded-full bg-card/95 border border-border px-2 py-1.5"
          style="box-shadow:var(--shadow-card);"
        >
          <button type="button" phx-click="prev" disabled={@index == 0} class={ctl_class(@index == 0)}>
            ‹
          </button>
          <button type="button" phx-click="toggle_pause" class={ctl_class(false)}>
            {if @paused?, do: "▶", else: "❚❚"}
          </button>
          <button
            type="button"
            phx-click="next"
            disabled={@index >= length(@keys) - 1}
            class={ctl_class(@index >= length(@keys) - 1)}
          >
            ›
          </button>
          <span class="text-[12px] text-inkFaint tabular-nums pl-1 pr-2">
            {@index + 1} / {length(@keys)}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp ctl_class(disabled?) do
    [
      "w-9 h-9 grid place-items-center rounded-lg bg-card border border-border text-inkSoft",
      "text-[14px] leading-none transition-colors",
      if(disabled?, do: "opacity-40", else: "hover:text-ink hover:border-borderStrong")
    ]
  end

  ## ---------- slide/take plumbing ----------

  defp pinned_variant(%{"variant" => variant}) do
    if variant in Slides.variants(), do: variant
  end

  defp pinned_variant(_params), do: nil

  defp current_key(assigns), do: Enum.at(assigns.keys, assigns.index)

  defp current_take(assigns), do: Map.get(assigns.takes, to_string(current_key(assigns)))

  defp next_media_url(assigns) do
    case Enum.at(assigns.keys, assigns.index + 1) do
      nil -> nil
      key -> assigns.takes |> Map.get(to_string(key)) |> media_url()
    end
  end

  defp media_url(nil), do: nil
  defp media_url(take), do: take.media_url

  # Recorded slides use their real length; un-narrated ones use the dwell time.
  defp estimated_minutes(assigns) do
    ms =
      Enum.reduce(assigns.keys, 0, fn key, acc ->
        case Map.get(assigns.takes, to_string(key)) do
          %{duration_ms: ms} when is_integer(ms) and ms > 0 -> acc + ms
          _ -> acc + @fallback_ms
        end
      end)

    max(1, round(ms / 60_000))
  end

  defp cta_path(nil), do: ~p"/register"
  defp cta_path(_user), do: ~p"/campaigns/new"

  ## ---------- live registry numbers ----------

  defp landing_countries do
    counts =
      case Company.market_totals() do
        {:ok, totals} -> totals
        _ -> %{}
      end

    Enum.map(Markets.all(), fn m ->
      %{name: m.name, available: m.available, count: m.available && counts[m.market]}
    end)
  end

  defp registry_total(countries) do
    countries |> Enum.map(&(&1.count || 0)) |> Enum.sum()
  end
end
