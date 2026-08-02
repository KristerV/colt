# The demo deck — guide for agents

The narrated slideshow at `/demo` that prospects watch instead of a live demo.
This document is the contract: read it before touching any deck file.

**Read `docs/design.md` too.** Slides are marketing UI and obey Calm Pro — Inter
only, `<em>` for the one accent word per heading, restrained colour, everything
in bounded cards.

---

## 1. The shape of it

Two ideas carry the whole feature:

**Slides are code.** A slide is a HEEx function in `ColtWeb.Deck.Slides`. There
is deliberately no slide editor and no slide table — you get full HTML/CSS, real
product numbers at render time, and a git diff when the pitch changes.

**Narration is one clip per slide.** Each slide has its own 20–60s webcam clip
rather than one long video of the whole talk. That is what makes the deck
forkable: a variant is an ordered subset of slides, and each slide brings its own
narration, so the short deck is narrated the moment the long one is. It also
means a stale slide costs one 40-second re-record, not a new take of everything.

### Files

| Path | What it is |
|---|---|
| `lib/colt_web/deck/slides.ex` | **The content.** Slide functions, per-variant order, the shared `d-*` stylesheet. |
| `lib/colt_web/live/deck_live.ex` | `/demo` — the player. |
| `lib/colt_web/live/admin/deck_studio_live.ex` | `/admin/deck` — the recorder. |
| `lib/colt/deck/manifest.ex` | `priv/deck/manifest.json` — the *only* record of what's recorded. |
| `lib/colt/deck/transcode.ex` | ffmpeg normalisation. Don't touch without reading §6. |
| `assets/js/deck.js` | `DeckPlayer` and `DeckRecorder` hooks. |
| `priv/static/media/deck/*.mp4` | The clips. Committed to git. |
| `test/colt_web/live/deck_studio_test.exs` | Smoke coverage for both surfaces. |

### Routes

- `/demo` — plays whichever variant `ab_funnel` assigned this visitor
- `/demo/long`, `/demo/short` — pin a variant, for linking a specific cut
- `/admin/deck`, `/admin/deck/:slide_key` — the studio (admin only)
- `/admin/ab` — the drop-off funnel

---

## 2. Editing a slide

Slides live in `slides.ex` between the `## ---------- a · hook ----------`
style banners. Each is a private function component returning the slide body:

```elixir
defp problem(assigns) do
  ~H"""
  <div class="d-pad flex flex-col justify-center h-full">
    <div class="d-kicker text-inkFaint">The stack you're replacing</div>
    <h2 class="d-h2 mt-[1cqw]">One tool, not <em>five</em>.</h2>
    ...
  </div>
  """
end
```

Copy edits are just edits. Nothing else needs to change.

### Adding a slide

Four places, in this order:

1. Write the `defp <key>(assigns)` component.
2. Add `<key>` to `@long` and/or `@short` at the top of the module.
3. Add a `def title(:<key>), do: "…"` clause — this is the studio's slide-list label.
4. Add the `:<key> -> <key>(assigns)` line to `slide/1`'s dispatch.

Miss step 4 and it raises `CaseClauseError` at render. Miss step 3 and it raises
`FunctionClauseError`. There's no registry to keep in sync beyond these.

### Removing a slide

Reverse of the above, plus delete its entry from `priv/deck/manifest.json` and
its `.mp4` from `priv/static/media/deck/` — nothing prunes those automatically
once the slide key is gone.

---

## 3. Layout rules — non-obvious and load-bearing

Every slide renders into a **16:9 stage that is `container-type: size`**. That
means:

**All sizing is in `cqw`** (percent of stage width), never `px` or `rem`. This is
what makes the deck identical on a laptop and a projector, and identical between
the player and the studio preview. `mt-[1.4cqw]`, `gap-[0.9cqw]`,
`max-w-[62cqw]` — Tailwind arbitrary values take `cqw` fine.

**Use the `d-*` classes**, defined in `Slides.styles/1`:

| Class | Use |
|---|---|
| `d-pad` | The slide's outer padding. Every slide's root div starts with it. |
| `d-h1` `d-h2` `d-h3` `d-h4` | Headings, 5.4 → 1.75cqw |
| `d-lead` `d-body` `d-fine` | Prose, 1.9 / 1.35 / 1.02cqw |
| `d-kicker` | The small uppercase label above a heading |
| `d-num` `d-num-sm` | Big tabular numbers |
| `d-card` `d-cardhead` | The bounded box and its header strip |
| `d-chip` `d-dot` `d-step-no` `d-avatar` | Small pieces |
| `d-btn` | The CTA button |

**Tone overrides go through inline `style=`, not utility classes.** The `d-*`
rules are a plain stylesheet, so a Tailwind class loses the specificity fight.
Use the `tone_style/1`, `ring_style/1`, `ink_style/1` helpers at the bottom of
the module.

**Keep the bottom-right corner clear.** The talking-head bubble sits there
(`.deck-bubble`, 10.5cqw). `d-pad` already carries 9.5cqw of bottom padding as
its safe area — content is vertically centred inside that box, which lifts it
clear. Don't reduce that padding, and don't put content flush to the
bottom-right.

**Real numbers where they're cheap.** `slide/1` receives `registry_total` and
`countries` from the live database, so the hook slide's company count is true.
Prefer that over hardcoding when the figure exists.

---

## 4. Variants and the A/B test

`Slides.order/1` is the entire fork:

```elixir
@long  [:hook, :problem, :targeting, :enrichment, :sending, :cta]
@short [:hook, :problem, :targeting, :short_cta]
```

Adding a variant is a new `order/2` clause plus an entry in `variants/0` — not a
schema change.

Assignment comes from `ab_funnel`, which gives a visitor **one variant for the
whole site** (cookie, one year). So the same key that picks deck length also
drives whatever onboarding branches on later — it's one test, not two.

Tracking is already wired: one event per slide on first view (`slide_hook`,
`slide_problem`, …), plus `deck_started`, `deck_completed`, `cta_clicked`.
`AbFunnel.AdminLive` at `/admin/ab` orders steps by average position across
visitors and counts unique visitors per step, so you get a per-slide drop-off
funnel grouped by variant for free. **Don't add bespoke analytics** — add an
`AbFunnel.track/3` call if something new needs measuring.

A clip is shared by every variant the slide appears in. `hook` is in both decks,
so it's recorded once.

---

## 5. How narration is stored

**`priv/deck/manifest.json` is the only source of truth.** There is no database
table. Recording happens on a dev machine, so anything in Postgres would never
reach prod; the manifest is committed to git and ships with the repo.

```json
{"slides": {"hook": {
  "url": "/media/deck/hook-1785491570937.mp4",
  "content_type": "video/mp4",
  "duration_ms": 4649,
  "recorded_at": "2026-07-31T09:52:52Z"
}}}
```

`Colt.Deck.Manifest` is `read/0`, `put/2`, `delete/1`, `path/0`. The studio calls
`put`/`delete`; the player calls `read`. One clip per slide — recording again
replaces the entry *and* deletes the old file.

**Publishing is `git commit`.** The manifest plus `priv/static/media/deck/`.
There is no export step.

A slide with no clip still plays — the player holds it for `@fallback_ms`
(11s) so the deck is watchable before anything is recorded.

---

## 6. Things that will bite you

These each cost real debugging time. Don't undo them.

**`config/dev.exs` live-reload must exclude `priv/static/media/`.** The studio
writes clips into `priv/static/`, and the default watcher pattern matches media
files — so saving a clip full-page-reloaded the browser mid-upload and destroyed
it. The exclusion is `(?!uploads/|media/)`. Symptom if reintroduced: uploads
never finish, the page silently resets, files appear on disk with no manifest
entry.

**Chromium on Linux cannot encode H.264.** Asking `MediaRecorder` for
`video/mp4` yields VP9-in-MP4 — plays in Chrome, not in Safari, and the
container lies about its contents so you can't detect it by filename. Every clip
is therefore run through `Colt.Deck.Transcode` (H.264/AAC, 540p, faststart) on
the dev machine. Prod never transcodes and needs no ffmpeg.

**Uploads go in 1 MB chunks, and recording is capped at 540p/600 kbps.**
LiveView's default 64 KB chunk costs a round trip *and* a full re-render each; at
the browser's default bitrate a 35s take was ~9 MB and never finished. Don't
raise the recording quality — 540p is what gets stored anyway, since the bubble
renders at ~150 px.

**Nothing slow may run inside `consume_uploaded_entry`.** LiveView calls
`:consume_done` on the upload channel *after* the callback returns, and the
channel closes itself once idle past `chunk_timeout`. `store_clip` copies the
bytes out fast, then transcodes.

**Tests share `priv/` with the dev checkout.** `deck_studio_test.exs` snapshots
`manifest.json` and restores it in `on_exit`. Keep that helper — without it,
running the suite wipes real recordings.

---

## 7. Recording (what the human does)

`/admin/deck`, in a real browser with a camera. The studio shows the actual slide
so what's framed is what the prospect sees; the bubble preview appears only while
recording, in the same corner and shape as playback.

- Pick the deck (left) — a filter on the slide list, nothing more.
- Space = record/stop, N = next slide.
- A slide has either a record button or its clip + Delete, never both. Replacing
  means deleting first.
- The device labels next to the button name the actual camera and mic. Check
  them — a stand-in stream looks identical to a real one until you read the label.

Narrate **concepts, not layout**. "Every reply lands here, sorted by intent"
survives a redesign; "click the blue button top-right" doesn't.

---

## 8. Verifying a change

```bash
mix format && mix compile --warnings-as-errors
MIX_ENV=test mix test test/colt_web/live/deck_studio_test.exs
```

The four tests cover: record button on an empty slide, clip + two-step Delete on
a recorded one, the deck selector filtering the list, and `/demo/long` vs
`/demo/short` playing 6 vs 4 slides.

For visual changes, look at the slide — `/demo/long` and the studio render the
same component, so the studio is the faster loop.

To exercise the full record→save path without a human at a webcam, drive a
browser yourself: launch chromium with `--use-fake-device-for-media-stream` and
`--use-fake-ui-for-media-stream` (a real browser-level fake camera, so the code
path is the same one a human takes — do *not* monkey-patch `getUserMedia`, which
produces a stream that behaves differently and, if left injected in a shared
browser, silently records the fake camera instead of the human). Log in via the
magic link in `/dev/mailbox`, click `#studio-record`, wait, click again, then
assert on `priv/deck/manifest.json`. Capture the page console and WebSocket
frames — the upload bugs above were only ever visible there.

Run your own server on a spare port with output to a log file rather than
sharing the developer's. Two `mix` processes fight over the build lock, which
blocks the code reloader and makes the studio look frozen.

**Never patch these files with `python`/`sed` heredocs.** Use Edit. Silent
non-matching replacements have mangled this template before.
