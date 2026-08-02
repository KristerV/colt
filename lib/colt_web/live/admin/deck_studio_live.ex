defmodule ColtWeb.Admin.DeckStudioLive do
  @moduledoc """
  `/admin/deck` — record the narration that plays on `/demo`.

  One clip per slide, recorded against the real slide so what you see while
  talking is what the prospect sees. Clips are captured in the browser
  (`MediaRecorder`) and normalised to H.264/AAC by `Colt.Deck.Transcode` on the
  way in, because what a browser hands you for "video/mp4" varies by platform
  and Safari is unforgiving about it. All of that happens on your dev machine —
  prod only serves the finished files.

  A clip is a file under `priv/static/media/deck/` plus a line in
  `Colt.Deck.Manifest`, written here and nowhere else. Recording a slide again
  replaces what was there, file included — no take history to reason about, so
  what the studio shows is always what plays.

  The deck selector is only a filter on the slide list; you work through one
  deck at a time. A clip is shared by every deck the slide appears in — `cta`
  closes both, so you record it once.
  """
  use ColtWeb, :live_view

  require Logger

  alias Colt.Deck.Manifest
  alias Colt.Deck.Transcode
  alias ColtWeb.Admin.Summary
  alias ColtWeb.Deck.Slides

  @media_dir "media/deck"
  @max_clip_bytes 300_000_000
  @channel_timeout :timer.minutes(2)
  # LiveView's default 64KB chunk costs a socket round trip *and* a full
  # re-render each, which for a multi-megabyte clip means hundreds of them and
  # an upload that crawls. 1MB chunks cut that by ~16x.
  @chunk_size 1_000_000
  @default_deck "features"

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Deck studio",
       keys: Slides.order(@default_deck),
       deck: @default_deck,
       recording?: false,
       saving?: false,
       duration_ms: nil,
       camera: :arming,
       camera_error: nil,
       video_label: nil,
       audio_label: nil,
       confirm_delete?: false
     )
     # Generous chunk_timeout: the LiveView blocks on ffmpeg while encoding a
     # take, and an upload channel that is waiting to be consumed must outlive
     # that pause rather than close underneath it.
     |> allow_upload(:clip,
       accept: ~w(.mp4 .webm),
       max_entries: 1,
       max_file_size: @max_clip_bytes,
       chunk_size: @chunk_size,
       chunk_timeout: @channel_timeout,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  def handle_params(params, _uri, socket) do
    key =
      case params["slide_key"] do
        nil ->
          hd(socket.assigns.keys)

        given ->
          Enum.find(socket.assigns.keys, hd(socket.assigns.keys), &(to_string(&1) == given))
      end

    {:noreply,
     socket
     |> assign(slide_key: key, confirm_delete?: false)
     |> load_takes()}
  end

  ## ---------- events ----------

  # Purely a filter — which deck's slides you're working through. It has no
  # bearing on who hears the take.
  def handle_event("select_deck", %{"deck" => deck}, socket) do
    keys = Slides.order(deck)
    slide_key = if socket.assigns.slide_key in keys, do: socket.assigns.slide_key, else: hd(keys)

    {:noreply,
     socket
     |> assign(deck: deck, keys: keys, slide_key: slide_key)
     |> load_takes()}
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("camera_ready", params, socket) do
    {:noreply,
     assign(socket,
       camera: :ready,
       camera_error: nil,
       video_label: params["video_label"],
       audio_label: params["audio_label"]
     )}
  end

  def handle_event("camera_error", %{"message" => message}, socket) do
    {:noreply, assign(socket, camera: :error, camera_error: message)}
  end

  def handle_event("retry_camera", _params, socket) do
    {:noreply,
     socket |> assign(camera: :arming, camera_error: nil) |> push_event("deck:arm", %{})}
  end

  def handle_event("recording_started", _params, socket) do
    {:noreply,
     assign(socket, recording?: true, saving?: false, duration_ms: nil, confirm_delete?: false)}
  end

  # The clip uploads and is re-encoded after this, which takes a few seconds.
  # Driven by an assign rather than the upload's own entries so there is always
  # something on screen between "stopped talking" and "clip saved".
  def handle_event("recording_stopped", %{"duration_ms" => ms}, socket) do
    {:noreply, assign(socket, recording?: false, saving?: true, duration_ms: ms)}
  end

  def handle_event("next_slide", _params, socket) do
    keys = socket.assigns.keys
    index = Enum.find_index(keys, &(&1 == socket.assigns.slide_key)) || 0
    next = Enum.at(keys, min(index + 1, length(keys) - 1))

    {:noreply, push_patch(socket, to: ~p"/admin/deck/#{next}")}
  end

  # Two-step delete in the button itself: first click arms it, second click
  # does it. Beats a browser confirm dialog for something you'll do often, and
  # it disarms itself so a stray click can't sit there loaded.
  def handle_event("delete", _params, socket) do
    if socket.assigns.confirm_delete? do
      remove_file(socket.assigns.take)
      Manifest.delete(socket.assigns.slide_key)

      {:noreply, socket |> assign(confirm_delete?: false) |> load_takes()}
    else
      Process.send_after(self(), :disarm_delete, 4000)
      {:noreply, assign(socket, confirm_delete?: true)}
    end
  end

  def handle_info(:disarm_delete, socket) do
    {:noreply, assign(socket, confirm_delete?: false)}
  end

  ## ---------- files ----------

  # The manifest points at `/media/deck/…`; the bytes sit under priv/static and
  # travel in the repo. Writes and deletes both go through here, so a clip can
  # never be written to one place and looked for in another.
  defp media_dir, do: Path.join([:code.priv_dir(:colt), "static", @media_dir])
  defp media_path(filename), do: Path.join(media_dir(), filename)
  defp media_url(filename), do: "/#{@media_dir}/#{filename}"

  defp remove_file(%{media_url: url}) when is_binary(url) do
    File.rm(media_path(Path.basename(url)))
  end

  defp remove_file(_take), do: :ok

  ## ---------- upload ----------

  defp handle_progress(:clip, entry, socket) do
    if entry.done? do
      save_clip(socket, entry)
    else
      {:noreply, socket}
    end
  end

  # Anything that goes wrong between "you stopped talking" and "the take is on
  # disk" must land on screen. Left to crash, the LiveView dies and reconnects
  # silently — the take is gone and the studio looks like you never pressed
  # record.
  #
  # The filename is settled before anything can fail, so the failure paths know
  # which file to take back out — a half-saved take must not leave a clip behind
  # for you to commit. The timestamp busts the browser's cache on re-record.
  defp save_clip(socket, entry) do
    slide_key = to_string(socket.assigns.slide_key)
    previous = socket.assigns.take
    filename = "#{slide_key}-#{System.system_time(:millisecond)}.mp4"

    try do
      {content_type, note} = store_clip(socket, entry, filename)

      Manifest.put(slide_key, %{
        media_url: media_url(filename),
        media_content_type: content_type,
        duration_ms: socket.assigns.duration_ms,
        recorded_at: DateTime.utc_now()
      })

      # The clip this one replaces has to go, or it sits in the media directory
      # forever and ends up in the commit.
      remove_file(previous)

      {:noreply, socket |> assign(saving?: false) |> flash_for(note) |> load_takes()}
    rescue
      error ->
        Logger.error("deck take failed: " <> Exception.format(:error, error, __STACKTRACE__))

        {:noreply,
         failed(socket, filename, "That take could not be saved: #{Exception.message(error)}.")}
    catch
      :exit, reason ->
        Logger.error("deck take exited: #{inspect(reason)}")

        {:noreply,
         failed(socket, filename, "That take could not be saved — the upload closed early.")}
    end
  end

  defp failed(socket, filename, message) do
    File.rm(media_path(filename))

    socket
    |> assign(saving?: false)
    |> put_flash(:error, message <> " Nothing was recorded — try again.")
    |> load_takes()
  end

  defp flash_for(socket, nil) do
    put_flash(socket, :info, "Recorded #{Slides.title(socket.assigns.slide_key)}.")
  end

  defp flash_for(socket, note), do: put_flash(socket, :error, note)

  # Normalise the codec before storing — see Colt.Deck.Transcode for why the
  # container's own claim about its contents can't be trusted.
  defp store_clip(socket, entry, filename) do
    # Nothing slow may happen inside the consume callback. LiveView calls
    # `:consume_done` on the upload channel *after* this returns, and the channel
    # closes itself once it has been idle for `chunk_timeout` — so a long encode
    # in here kills the channel and the reply lands on a dead process. Copy the
    # bytes out, release the channel, then transcode.
    raw =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        scratch = Path.join(System.tmp_dir!(), "deck-#{System.unique_integer([:positive])}.src")
        File.cp!(path, scratch)
        {:ok, scratch}
      end)

    {:ok, binary, content_type, note} =
      Transcode.run(File.read!(raw), entry.client_type || "video/mp4")

    File.rm(raw)

    File.mkdir_p!(media_dir())
    File.write!(media_path(filename), binary)

    {content_type, note}
  end

  # priv/deck/manifest.json is the whole state — what the studio shows and what
  # prod plays are the same file, so "commit the repo" is the entire publish
  # step.
  defp load_takes(socket) do
    entries = Manifest.read()

    assign(socket,
      take: Map.get(entries, to_string(socket.assigns.slide_key)),
      recorded: MapSet.new(Map.keys(entries)),
      takes: entries,
      stats: deck_stats(socket.assigns.deck, entries)
    )
  end

  # How long a variant actually runs: the sum of its recorded clips. Slides with
  # no clip contribute nothing rather than the player's 11s dwell — this is
  # meant to answer "how long is the talk I've recorded", not "how long does the
  # deck sit on screen".
  defp deck_stats(deck, takes) do
    keys = Slides.order(deck)

    {recorded, ms} =
      Enum.reduce(keys, {0, 0}, fn key, {n, acc} ->
        case Map.get(takes, to_string(key)) do
          %{duration_ms: d} when is_integer(d) and d > 0 -> {n + 1, acc + d}
          _ -> {n, acc}
        end
      end)

    %{total: length(keys), recorded: recorded, ms: ms}
  end

  defp runtime_label(0), do: "—"

  defp runtime_label(ms) do
    seconds = div(ms, 1000)

    "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  ## ---------- render ----------

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <Slides.styles />

      <div class="mb-4">
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-[210px_1fr] gap-4 items-start">
        <div class="flex flex-col gap-3">
          <%!-- Which deck's slides to work through. Nothing more — a take
                recorded here plays in every deck the slide appears in. --%>
          <form phx-change="select_deck">
            <select
              name="deck"
              class="w-full rounded-lg border border-border bg-card px-3 py-2 text-[13px] text-ink"
              style="box-shadow:var(--shadow);"
            >
              <option
                :for={deck <- Slides.variants()}
                value={deck}
                selected={@deck == deck}
              >
                <% s = deck_stats(deck, @takes) %>
                {deck_label(deck)} · {s.total} slides · {runtime_label(s.ms)}
              </option>
            </select>
          </form>

          <%!-- What's actually in the can for this deck. The runtime is the sum
                of recorded clips, so it only reads as the real talk length once
                every slide has one. --%>
          <div
            class="bg-card border border-border rounded-[11px] px-3.5 py-3"
            style="box-shadow:var(--shadow);"
          >
            <div class="text-[10.5px] font-semibold tracking-[0.08em] uppercase text-inkFaint">
              Runtime
            </div>
            <div class="text-[24px] font-bold tracking-[-0.02em] text-ink tabular-nums leading-none mt-1">
              {runtime_label(@stats.ms)}
            </div>
            <div class={[
              "text-[12px] tabular-nums mt-1.5",
              if(@stats.recorded == @stats.total,
                do: "text-green font-semibold",
                else: "text-inkSoft"
              )
            ]}>
              {@stats.recorded} / {@stats.total} recorded
            </div>
          </div>

          <div
            class="bg-card border border-border rounded-[11px] p-2"
            style="box-shadow:var(--shadow);"
          >
            <.link
              :for={key <- @keys}
              patch={~p"/admin/deck/#{key}"}
              class={[
                "flex items-center justify-between gap-2 rounded-lg px-3 py-2 text-[13px] no-underline",
                key == @slide_key && "bg-accentSoft text-accent font-semibold",
                key != @slide_key && "text-inkSoft hover:bg-paperAlt"
              ]}
            >
              <span class="truncate">{Slides.title(key)}</span>
              <span
                class="w-2 h-2 rounded-full shrink-0"
                style={
                  if MapSet.member?(@recorded, to_string(key)),
                    do: "background:var(--green);",
                    else: "background:var(--borderStrong);"
                }
              />
            </.link>
          </div>

          <.link
            navigate={~p"/demo/#{@deck}"}
            class="rounded-lg border border-borderStrong bg-card px-3 py-2 text-[13px] text-inkSoft text-center no-underline"
          >
            Play deck →
          </.link>
        </div>

        <div id="studio-camera" phx-hook="DeckRecorder">
          <div class="deck-stage">
            <%!-- Same numbers the cover advertises on /demo, so the slide you
                  frame yourself against is the one the prospect sees. --%>
            <Slides.slide
              key={@slide_key}
              registry_total={512_000}
              countries={[]}
              slide_count={@stats.total - 1}
              minutes={max(1, round(@stats.ms / 60_000))}
            />

            <%!-- Same element, same class, same corner as the player's bubble, so
                  what you frame yourself against while talking is exactly what the
                  prospect sees. Hidden rather than removed: the hook holds a
                  reference to it and the srcObject must survive the patch. --%>
            <video id="studio-preview" class="deck-bubble" hidden={!@recording?} playsinline muted />
          </div>

          <%!-- One clip per slide, so this is either the clip or the button that
                makes one — never both. Replacing means deleting first, which
                leaves nothing to explain. --%>
          <div :if={@take} class="flex items-center gap-3 mt-3">
            <span class="w-2 h-2 rounded-full shrink-0" style="background:var(--green);" />
            <div class="text-[14px] text-ink tabular-nums font-medium">
              {duration_label(@take.duration_ms)}
            </div>
            <div :if={@take.recorded_at} class="text-[12.5px] text-inkFaint tabular-nums">
              recorded {Calendar.strftime(@take.recorded_at, "%d %b %H:%M")}
            </div>
            <button
              type="button"
              phx-click="delete"
              class="rounded-lg border px-3 py-1.5 text-[13px] font-medium"
              style={
                if @confirm_delete?,
                  do: "background:var(--red);border-color:var(--red);color:#fff;",
                  else:
                    "background:var(--card);border-color:var(--borderStrong);color:var(--inkSoft);"
              }
            >
              {if @confirm_delete?, do: "Click again to delete", else: "Delete"}
            </button>
          </div>

          <div :if={is_nil(@take)} class="flex items-center gap-3 mt-3">
            <button
              type="button"
              id="studio-record"
              class="rounded-lg px-4 py-2.5 text-[14px] font-semibold text-white"
              style={
                if @recording?,
                  do: "background:var(--red);",
                  else: "background:var(--accent);box-shadow:var(--shadow);"
              }
            >
              {if @recording?, do: "■ Stop & save", else: "● Record this slide"}
            </button>

            <span
              :if={@recording?}
              class="flex items-center gap-2 text-[13px] font-semibold tabular-nums"
              style="color:var(--red);"
            >
              <span class="w-2.5 h-2.5 rounded-full animate-pulse" style="background:var(--red);" />
              REC <span id="studio-timer" phx-update="ignore">0:00</span>
            </span>

            <%!-- The clip uploads and is re-encoded after you stop, which takes a
                  few seconds. Without this the studio looks idle and you can't
                  tell a slow save from a failed one. --%>
            <span
              :if={@saving?}
              class="flex items-center gap-2 text-[13px] font-semibold"
              style="color:var(--accent);"
            >
              <span class="w-2.5 h-2.5 rounded-full animate-pulse" style="background:var(--accent);" />
              Saving…
            </span>

            <%!-- Which devices you're actually recording through. A stand-in
                  stream looks identical to a real one until you read the label. --%>
            <span
              :if={!@recording? && !@saving? && @camera == :ready}
              class="text-[12.5px] text-inkFaint"
            >
              {@video_label || "unnamed camera"} · {@audio_label || "no microphone"}
            </span>

            <span
              :if={@camera == :error}
              class="text-[12.5px] flex items-center gap-2"
              style="color:var(--red);"
            >
              {@camera_error}
              <button
                type="button"
                phx-click="retry_camera"
                class="rounded-lg border border-borderStrong bg-card px-2.5 py-1 text-[12px] text-ink"
              >
                Enable camera
              </button>
            </span>
          </div>

          <%!-- The teleprompter. Only ever shown here — the prospect never sees
                the script, so it is sized for reading at arm's length rather
                than in the slide's cqw scale. --%>
          <div
            class="bg-card border border-border rounded-[11px] p-5 mt-4"
            style="box-shadow:var(--shadow);"
          >
            <div class="text-[10.5px] font-semibold tracking-[0.08em] uppercase text-inkFaint mb-2">
              Script — {Slides.title(@slide_key)}
            </div>
            <div class="text-[16px] leading-[1.65] text-ink whitespace-pre-line">
              {Slides.script(@slide_key)}
            </div>
          </div>

          <%!-- The recorder hook hands blobs to LiveView via this.upload/2, which
                needs a live file input on the page to bind them to. Hidden: the
                clip never comes from a file picker. --%>
          <form id="deck-uploads" phx-change="noop" phx-submit="noop" class="hidden">
            <.live_file_input upload={@uploads.clip} />
          </form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp duration_label(nil), do: "—"
  defp duration_label(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp deck_label("features"), do: "Features"
  defp deck_label("solving_emails"), do: "Solving emails"
  defp deck_label(deck), do: String.capitalize(deck)
end
