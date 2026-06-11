defmodule ColtWeb.Sending.PitchLive do
  @moduledoc """
  /campaigns/:id/pitch — "what we sell" context that feeds EmailWriter.

  Domain input autosaves on blur. On change it kicks off
  `Colt.Services.Sending.PitchSummary` in a Task and locks the summary
  textarea until the task reports back (PubSub `pitch:<id>`).
  """

  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, Pitch}
  alias Colt.Services.Sending.PitchSummary
  alias ColtWeb.Components.Liid
  alias Phoenix.PubSub

  @pubsub Colt.PubSub

  on_mount {ColtWeb.LiveUserAuth, :live_plan_required}
  on_mount {ColtWeb.Sending.PanicHook, :default}

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        {:ok, pitch} = Pitch.upsert_for_campaign(campaign.id, actor: actor)

        if connected?(socket), do: PubSub.subscribe(@pubsub, topic(pitch.id))

        {:ok,
         assign(socket,
           page_title: gettext("Pitch — %{name}", name: campaign.name),
           campaign: campaign,
           pitch: pitch,
           domain: pitch.domain || "",
           summary: effective_summary(pitch),
           saved_at: nil
         )}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_event("set_domain", %{"value" => domain}, socket) do
    domain = String.trim(domain)
    pitch = socket.assigns.pitch
    actor = socket.assigns.current_user

    if domain == "" or domain == pitch.domain do
      {:noreply, assign(socket, domain: domain)}
    else
      ref = random_ref()

      {:ok, pitch} =
        Pitch.set_domain(pitch, domain, ref, actor: actor)

      kick_off_fetch(pitch.id, ref, actor)

      {:noreply,
       socket
       |> assign(pitch: pitch, domain: domain, summary: "")
       |> mark_saved()}
    end
  end

  def handle_event("set_summary", %{"value" => v}, socket) do
    pitch = socket.assigns.pitch
    actor = socket.assigns.current_user

    if pitch.fetching? do
      {:noreply, socket}
    else
      {:ok, pitch} = Pitch.set_user_summary(pitch, v, actor: actor)
      {:noreply, socket |> assign(pitch: pitch, summary: v) |> mark_saved()}
    end
  end

  def handle_info({:pitch_updated, pitch_id}, socket) do
    if socket.assigns.pitch.id == pitch_id do
      actor = socket.assigns.current_user
      {:ok, pitch} = Pitch.get(pitch_id, actor: actor)

      {:noreply,
       assign(socket,
         pitch: pitch,
         domain: pitch.domain || "",
         summary: effective_summary(pitch)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp kick_off_fetch(pitch_id, ref, actor) do
    parent = self()

    Task.start(fn ->
      _ = PitchSummary.run(pitch_id, ref, actor: actor)
      send(parent, {:pitch_updated, pitch_id})
    end)
  end

  defp random_ref, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  defp effective_summary(%{user_summary: u, ai_summary: a}), do: u || a || ""

  defp topic(pitch_id), do: "pitch:#{pitch_id}"

  defp mark_saved(socket), do: assign(socket, saved_at: DateTime.utc_now())

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:pitch}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="w-full max-w-[760px] mx-auto pb-16">
        <Liid.headline
          kicker={gettext("Sending · Pitch")}
          sub={
            gettext(
              "What you sell, in your words. We read your site once and draft this for you — the AI writer reuses it on every outbound email."
            )
          }
        >
          {raw(gettext("The <em>offer</em> behind every email."))}
        </Liid.headline>

        <div class="mt-10">
          <div class="font-mono text-[10px] tracking-[0.14em] uppercase text-ink55 mb-2.5">
            {gettext("Your domain")}
          </div>
          <form phx-change="set_domain" class="block">
            <input
              type="text"
              name="value"
              value={@domain}
              phx-debounce="blur"
              placeholder="liid.app"
              class="w-full px-5 py-3 border border-ink20 border-l-2 bg-paper rounded-[2px] text-[13.5px] text-ink outline-none placeholder:text-ink40 font-mono"
              style="border-left-color: var(--accent);"
            />
          </form>
          <div class="mt-1.5 font-mono text-[10px] text-ink40">
            {gettext(
              "press tab or click out to fetch. changing the domain re-fetches and overwrites the summary below."
            )}
          </div>
        </div>

        <div class="mt-8">
          <div class="flex items-center justify-between mb-2.5">
            <div class="font-mono text-[10px] tracking-[0.14em] uppercase text-ink55">
              {gettext("What you sell")}
            </div>
            <div
              :if={@pitch.fetching?}
              class="font-mono text-[10px] tracking-[0.06em] inline-flex items-center gap-1.5"
              style="color: var(--accent);"
            >
              <span
                class="w-[5px] h-[5px] rounded-full"
                style="background: var(--accent); animation: liid-pulse 1.4s ease-in-out infinite;"
              /> {gettext("reading site…")}
            </div>
          </div>
          <form phx-change="set_summary" class="block">
            <textarea
              name="value"
              rows="10"
              phx-debounce="600"
              disabled={@pitch.fetching?}
              placeholder={
                if @pitch.fetching?,
                  do: "",
                  else:
                    gettext("We'll fill this in once you set a domain. Or type your own pitch here.")
              }
              class={[
                "w-full px-5 py-4 bg-paper text-[13.5px] leading-[1.6] text-ink70 outline-none border border-ink20 rounded-[2px] resize-none font-sans block",
                @pitch.fetching? && "opacity-60 cursor-not-allowed"
              ]}
              style="field-sizing: content;"
            >{@summary}</textarea>
          </form>
          <div :if={@pitch.fetched_at} class="mt-1.5 font-mono text-[10px] text-ink40">
            {gettext("site last read %{at}.",
              at: Calendar.strftime(@pitch.fetched_at, "%Y-%m-%d %H:%M")
            )}
            <span :if={@pitch.user_summary not in [nil, ""]} class="text-ink55">
              {gettext("edited.")}
            </span>
          </div>
        </div>

        <div :if={@saved_at} class="mt-10 font-mono text-[11px] text-ink40">
          {gettext("saved %{at}", at: Calendar.strftime(@saved_at, "%H:%M:%S"))}
        </div>
      </div>
    </Layouts.app>
    """
  end
end
