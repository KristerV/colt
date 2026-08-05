defmodule ColtWeb.DeckLive do
  @moduledoc """
  `/demo` — the narrated demo deck prospects watch.

  Which slides play comes from `ColtWeb.Deck.Slides.order/1` keyed on the
  visitor's `ab_funnel` variant, so the two cuts are the same test as whatever
  the onboarding branches on later.

  There are no overlays: the cover and the close are ordinary slides. The deck
  simply sits on slide 0 until the cover's Play button is clicked, and stops on
  the last slide instead of covering it. That matters for the closing slide,
  whose buttons have to stay clickable.

  Playback is a single `<video>` element that never leaves the DOM: the Play
  button on the cover starts it inside the user's own click, which is what buys
  autoplay permission for every slide after it. Advancing is driven by the
  clip's `ended` event, so a slide is exactly as long as its narration. Slides
  with no recording yet fall back to a fixed dwell so the deck is watchable
  before anything has been recorded.

  The closing slide's three choices all record a `Colt.Resources.DemoLead`. Two
  of them collect a little more first, in a panel rendered *outside* the 16:9
  stage — inside it every size is in `cqw`, which would give a text input a
  ~13px font on a laptop and less on a phone.
  """
  use ColtWeb, :live_view

  require Logger

  alias Colt.Deck.Manifest
  alias Colt.Markets
  alias Colt.Resources.Company
  alias ColtWeb.Deck.Slides

  # How long an un-narrated slide stays up.
  @fallback_ms 11_000

  # `/demo` plays whatever variant ab_funnel assigned this visitor. `/demo/features`
  # and `/demo/solving_emails` pin one, so a specific cut can be linked to
  # directly.
  #
  # A pinned visit overwrites `ab_funnel_variant` for this LiveView, which is
  # what makes its events land under the deck the viewer actually watched.
  # `AbFunnel.track/2` reads that assign, not our `:variant`, so without this a
  # pinned visitor's slides are filed under whatever the cookie happened to say
  # — which files features slides under solving_emails and quietly corrupts the
  # funnel at /admin/ab rather than merely sitting outside it.
  def mount(params, _session, socket) do
    pinned = pinned_variant(params)
    variant = pinned || socket.assigns[:ab_funnel_variant]
    keys = Slides.order(variant)
    countries = landing_countries()

    {:ok,
     assign(socket,
       page_title: "Liid, lühike ülevaade",
       variant: variant,
       ab_funnel_variant: variant,
       pinned?: pinned != nil,
       keys: keys,
       index: 0,
       takes: Manifest.read(),
       started?: false,
       paused?: false,
       fallback_ms: @fallback_ms,
       tracked: MapSet.new(),
       countries: countries,
       registry_total: registry_total(countries),
       # The closing slide's panel: nil, or the kind being collected.
       asking: nil,
       # false, or the kind that was submitted — the thank-you copy differs.
       submitted?: false,
       form_error: nil,
       contact: nil
     )}
  end

  # A demo link handed to a specific contact carries `?c=<campaign_contact_id>`.
  # It is optional and usually absent — a cold visitor has no contact — but when
  # present it prefills the form and lets the submission be mirrored into that
  # contact's thread.
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, contact: load_contact(params["c"]))}
  end

  ## ---------- events ----------

  def handle_event("start", _params, socket) do
    # `pinned` separates traffic you aimed at a cut from traffic the coin flip
    # sent there — the variant column can no longer tell you which.
    AbFunnel.track(socket, "deck_started", %{pinned: socket.assigns.pinned?})

    {:noreply,
     socket
     |> assign(started?: true, index: min(1, length(socket.assigns.keys) - 1))
     |> track_current_slide()}
  end

  # "Paused" means the deck stops moving on by itself — the clip on the current
  # slide still plays to the end. Advancing is the only thing it gates, which is
  # why the decision lives here rather than in the player.
  def handle_event("advance", _params, socket) do
    last = length(socket.assigns.keys) - 1

    cond do
      socket.assigns.paused? or not socket.assigns.started? ->
        {:noreply, socket}

      socket.assigns.index >= last ->
        AbFunnel.track(socket, "deck_completed")
        {:noreply, assign(socket, paused?: true)}

      true ->
        {:noreply, socket |> assign(index: socket.assigns.index + 1) |> track_current_slide()}
    end
  end

  # Stepping through by hand is a deliberate act — stop auto-advancing so the
  # deck doesn't yank the viewer off the slide they just chose. Landing back on
  # the cover puts the deck back in its un-started state, since that slide is
  # the Play button.
  def handle_event("goto", %{"index" => index}, socket) do
    # Parsed rather than String.to_integer/1: this is a client-pushed event, and
    # a non-numeric value would take the whole LiveView down.
    index =
      case index |> to_string() |> Integer.parse() do
        {n, _rest} -> n |> max(0) |> min(length(socket.assigns.keys) - 1)
        :error -> socket.assigns.index
      end

    cover? = Slides.cover?(Enum.at(socket.assigns.keys, index))

    {:noreply,
     socket
     |> assign(index: index, started?: not cover?, paused?: true, asking: nil)
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

  # "Try it" needs nothing from them — record the choice and send them to
  # registration. The other two open the panel.
  def handle_event("cta_choice", %{"kind" => "try_it"}, socket) do
    AbFunnel.track(socket, "cta_clicked", %{kind: "try_it"})
    submit_lead(socket, :try_it, %{})

    {:noreply, push_navigate(socket, to: ~p"/register")}
  end

  def handle_event("cta_choice", %{"kind" => kind}, socket)
      when kind in ~w(call_request not_a_fit) do
    AbFunnel.track(socket, "cta_clicked", %{kind: kind})

    {:noreply, assign(socket, asking: kind, form_error: nil)}
  end

  def handle_event("close_panel", _params, socket) do
    {:noreply, assign(socket, asking: nil, form_error: nil)}
  end

  # The panel closes itself on success, so a double-click on Send arrives with
  # nothing being asked. Without this clause the second one crashes the
  # LiveView and the visitor loses the thank-you screen for a lead that was in
  # fact recorded.
  def handle_event("submit_lead", _params, %{assigns: %{asking: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("submit_lead", params, socket) do
    kind = String.to_existing_atom(socket.assigns.asking)

    case validate(kind, params) do
      :ok ->
        socket |> submit_lead(kind, params) |> identify_lead(socket)
        AbFunnel.track(socket, "lead_submitted", %{kind: socket.assigns.asking})

        {:noreply, assign(socket, asking: nil, submitted?: kind, form_error: nil)}

      {:error, message} ->
        {:noreply, assign(socket, form_error: message)}
    end
  end

  defp validate(:call_request, params) do
    if String.trim(params["phone"] || "") == "" do
      {:error, "Palun jäta telefoninumber, muidu ei saa helistada."}
    else
      :ok
    end
  end

  defp validate(:not_a_fit, params) do
    if String.trim(params["message"] || "") == "" do
      {:error, "Kirjuta paari sõnaga, mida sa vajad."}
    else
      :ok
    end
  end

  # Deliberately not a bang call and not a `{:ok, _} =` match: this is the one
  # write on the page that must not cost the visitor their thank-you screen if
  # it fails (a contact deleted between page load and submit would trip the FK).
  defp submit_lead(socket, kind, params) do
    case build_lead(socket, kind, params) do
      {:ok, lead} ->
        Colt.Services.Discord.Notify.run(discord_message(lead))
        maybe_note(lead, socket.assigns.contact)
        {:ok, lead}

      {:error, reason} ->
        Logger.error("demo lead submit failed: #{inspect(reason)}")
        :error
    end
  end

  # The one identity call nothing can infer. A signed-in browser binds itself, but someone
  # who watches the deck on their phone and clicks the magic link on their laptop is two
  # visitors and neither completes the funnel. Binding the browser to the email here joins
  # them — retroactively, over the slides they already watched.
  #
  # Only fires for leads that carry an email, which today means prospects who arrived
  # through a personalised `?c=` link: the lead panels collect name/phone or a message,
  # never an address. Cold visitors stay per-browser until the form asks for one.
  defp identify_lead({:ok, %{email: email}}, socket) when is_binary(email) do
    AbFunnel.identify_by_email(socket, email)
  end

  defp identify_lead(_result, _socket), do: :ok

  defp build_lead(socket, kind, params) do
    assigns = socket.assigns
    contact = assigns.contact

    Colt.Resources.DemoLead.submit(kind, %{
      name: blank_to_nil(params["name"]) || contact_field(contact, :name),
      phone: blank_to_nil(params["phone"]) || contact_field(contact, :phone),
      email: blank_to_nil(params["email"]) || contact_field(contact, :email),
      message: blank_to_nil(params["message"]),
      variant: assigns.variant,
      visitor_id: assigns[:ab_funnel_visitor_id],
      slide: to_string(current_key(assigns)),
      campaign_contact_id: contact && contact.id
    })
  end

  # A lead that came in through a personalised link is worth seeing in the
  # conversation itself, not only in the admin list. The visitor has no actor,
  # so this write is unauthorised by necessity and the note has no author.
  defp maybe_note(_lead, nil), do: :ok

  defp maybe_note(lead, contact) do
    with {:ok, thread} <- Colt.Resources.Thread.for_contact(contact.id, authorize?: false),
         {:ok, _note} <-
           Colt.Resources.Note.create_system(thread.id, note_body(lead), authorize?: false) do
      :ok
    else
      # A contact with no thread yet is the common case and not worth surfacing
      # to the visitor; anything else is worth knowing about, since a swallowed
      # error here means the note silently never appears in the conversation.
      {:error, %Ash.Error.Query.NotFound{}} ->
        :ok

      {:error, reason} ->
        Logger.warning("demo lead note failed for contact #{contact.id}: #{inspect(reason)}")
        :ok
    end
  end

  defp note_body(lead) do
    """
    Demo (#{lead.variant}): #{kind_label(lead.kind)}
    #{[lead.name, lead.phone, lead.email] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")}
    #{lead.message || ""}
    """
    |> String.trim()
  end

  # Discord rejects a webhook body over 2000 characters outright, so an
  # over-long message would lose the whole alert rather than just its tail.
  defp discord_message(lead) do
    details =
      [lead.name, lead.phone, lead.email, lead.message]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(" · ")

    "Demo lead (#{lead.variant}): #{kind_label(lead.kind)} · #{details}"
    |> String.slice(0, 1900)
  end

  defp kind_label(:call_request), do: "tahab kõnet"
  defp kind_label(:not_a_fit), do: "ei sobi"
  defp kind_label(:try_it), do: "läks registreeruma"

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp contact_field(nil, _field), do: nil
  defp contact_field(%{person: %{} = person}, field), do: Map.get(person, field)
  defp contact_field(_contact, _field), do: nil

  defp load_contact(nil), do: nil

  defp load_contact(id) do
    case Colt.Resources.CampaignContact.get(id, load: [:person], authorize?: false) do
      {:ok, contact} -> contact
      _ -> nil
    end
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
          slide_count={length(@keys) - 1}
          minutes={estimated_minutes(assigns)}
        />

        <video
          id="deck-video"
          class="deck-bubble"
          hidden={is_nil(current_take(assigns))}
          phx-hook="DeckPlayer"
          playsinline
          data-src={media_url(current_take(assigns))}
          data-index={@index}
          data-started={to_string(@started?)}
          data-fallback-ms={@fallback_ms}
          data-next-src={next_media_url(assigns)}
          data-any-src={any_media_url(assigns)}
        />

        <div
          :if={@started?}
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
            {@index} / {length(@keys) - 1}
          </span>
        </div>
      </div>

      <%!-- Everything below sits outside .deck-stage on purpose: inside it all
            sizing is cqw, which makes form controls unreadably small. --%>
      <.panel :if={@asking} kind={@asking} contact={@contact} error={@form_error} />

      <div
        :if={@submitted?}
        class="fixed inset-0 z-20 grid place-items-center px-6"
        style="background:rgba(247,247,245,.96);"
      >
        <div class="text-center max-w-[420px]">
          <h2 class="text-[26px] font-bold tracking-[-0.02em] text-ink">
            Aitäh, sain kätte.
          </h2>
          <%!-- Someone who just said Liid isn't for them should not be
                promised a phone call. --%>
          <p class="text-[14px] text-inkSoft leading-[1.6] mt-3">
            {if @submitted? == :call_request,
              do: "Võtan sinuga peagi ise ühendust.",
              else: "Hea teada, aitäh et ütlesid."}
          </p>
          <.link
            navigate={~p"/"}
            class="inline-flex items-center justify-center mt-6 px-5 py-3 rounded-[8px] bg-accent text-white text-[14px] font-semibold no-underline"
          >
            Vaata Liidi kohta rohkem
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :kind, :string, required: true
  attr :contact, :any, default: nil
  attr :error, :string, default: nil

  defp panel(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-20 grid place-items-center px-6"
      style="background:rgba(35,32,28,.34);"
    >
      <form
        phx-submit="submit_lead"
        class="w-full max-w-[440px] bg-card border border-border rounded-[11px] p-6"
        style="box-shadow:var(--shadow-card);"
      >
        <div class="text-[10.5px] font-semibold tracking-[0.08em] uppercase text-inkFaint">
          {if @kind == "call_request", do: "Kõne", else: "Tagasiside"}
        </div>
        <h2 class="text-[21px] font-bold tracking-[-0.02em] text-ink mt-1">
          {if @kind == "call_request",
            do: "Jäta nimi ja number",
            else: "Mida sa tegelikult vajad?"}
        </h2>

        <div :if={@kind == "call_request"} class="flex flex-col gap-3 mt-5">
          <.field name="name" label="Nimi" value={prefill(@contact, :name)} />
          <.field name="phone" label="Telefon" value={prefill(@contact, :phone)} type="tel" />
        </div>

        <div :if={@kind == "not_a_fit"} class="mt-5">
          <label
            for="lead-message"
            class="text-[10.5px] tracking-[0.08em] uppercase text-inkFaint font-semibold"
          >
            Paari sõnaga
          </label>
          <textarea
            id="lead-message"
            name="message"
            rows="4"
            class="w-full mt-2 px-4 py-3 border border-borderStrong bg-card text-[15px] leading-[1.55] text-ink rounded-[8px] outline-none resize-y focus:border-accent focus:[box-shadow:0_0_0_3px_var(--accentSoft)]"
          ></textarea>
        </div>

        <div :if={@error} class="text-[12.5px] text-red mt-3">{@error}</div>

        <div class="flex items-center justify-end gap-2 mt-6">
          <button
            type="button"
            phx-click="close_panel"
            class="px-4 py-2.5 rounded-[8px] border border-borderStrong bg-card text-inkSoft text-[13px] font-semibold cursor-pointer"
          >
            Tagasi
          </button>
          <button
            type="submit"
            class="px-5 py-2.5 rounded-[8px] bg-accent text-white text-[13px] font-semibold cursor-pointer"
          >
            Saada
          </button>
        </div>
      </form>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :type, :string, default: "text"

  defp field(assigns) do
    ~H"""
    <div>
      <label
        for={"lead-#{@name}"}
        class="text-[10.5px] tracking-[0.08em] uppercase text-inkFaint font-semibold"
      >
        {@label}
      </label>
      <input
        id={"lead-#{@name}"}
        type={@type}
        name={@name}
        value={@value}
        class="w-full mt-2 px-4 py-3 border border-borderStrong bg-card text-[15px] text-ink rounded-[8px] outline-none focus:border-accent focus:[box-shadow:0_0_0_3px_var(--accentSoft)]"
      />
    </div>
    """
  end

  defp prefill(%{person: %{} = person}, field), do: Map.get(person, field)
  defp prefill(_contact, _field), do: nil

  defp ctl_class(disabled?) do
    [
      "w-9 h-9 grid place-items-center rounded-lg bg-card border border-border text-inkSoft",
      "text-[14px] leading-none transition-colors",
      if(disabled?, do: "opacity-40", else: "hover:text-ink hover:border-borderStrong")
    ]
  end

  ## ---------- slide/take plumbing ----------

  defp pinned_variant(%{"variant" => variant}) do
    normalised = String.replace(variant, "-", "_")
    if normalised in Slides.variants(), do: normalised
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

  # Any recorded clip in this deck, for the audio unlock — see `unlock()` in
  # deck.js. The next slide's clip is preferred (it's about to play anyway);
  # this is the fallback for when the next slide has none.
  defp any_media_url(assigns) do
    Enum.find_value(assigns.keys, fn key ->
      assigns.takes |> Map.get(to_string(key)) |> media_url()
    end)
  end

  defp media_url(nil), do: nil
  defp media_url(take), do: take.media_url

  # Recorded slides use their real length; un-narrated ones use the dwell time.
  # The cover is excluded — it holds until clicked, so it has no duration.
  defp estimated_minutes(assigns) do
    ms =
      assigns.keys
      |> Enum.reject(&Slides.cover?/1)
      |> Enum.reduce(0, fn key, acc ->
        case Map.get(assigns.takes, to_string(key)) do
          %{duration_ms: ms} when is_integer(ms) and ms > 0 -> acc + ms
          _ -> acc + @fallback_ms
        end
      end)

    max(1, round(ms / 60_000))
  end

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
