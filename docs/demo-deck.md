# The demo deck — guide for agents

The narrated slideshow at `/demo` that prospects watch instead of a live demo.
This document is the contract: read it before touching any deck file.

**Read `docs/design.md` too.** Slides are marketing UI and obey Calm Pro: Inter
only, restrained colour, everything in bounded cards.

**Two house rules override `docs/design.md` here:**

- **No `<em>` accent word in headings.** design.md asks for one italicised
  accent word per heading; the deck does not use it. Headings are plain.
- **No em-dashes** anywhere a prospect can read: slide copy, the closing
  panel, page titles. Use a comma, a colon, or a full stop. (Elixir comments
  and moduledocs are exempt, they match the rest of the codebase.)

Both read as tired AI tics at slide scale, where a heading is the only thing on
screen.

**Copy is Estonian and hardcoded**, not run through gettext. The deck is a
single-market pitch and its prose is dense enough that a second language is a
rewrite rather than a substitution. There is currently no English cut.

## 0. Slides are illustration, not reading

The narrator is talking over every slide. A slide that carries a paragraph
competes with him and loses; the viewer reads instead of listening, and both
channels come out worse.

So the budget for a slide is **a heading and one visual element**. No kickers,
no explanatory body copy under a card title, no footnote line summarising what
was just said. If a fact matters, it belongs in `script/1` and comes out of his
mouth. `f_filter` is the clearest case: one number narrowing to a smaller one,
no heading at all.

When you add a slide, the test is whether it still reads at a glance with the
sound off. If it needs a sentence to make sense, the sentence goes in the
script.

---

## 1. The shape of it

Three ideas carry the whole feature:

**Slides are code.** A slide is a HEEx function in `ColtWeb.Deck.Slides`. There
is deliberately no slide editor and no slide table — you get full HTML/CSS, real
product numbers at render time, and a git diff when the pitch changes.

**Everything is a slide.** The cover and the closing call-to-action are ordinary
slides, not overlays. That is what lets each variant open with its own hook and
close with working buttons.

**Narration is one clip per slide.** Each slide has its own 20–60s webcam clip
rather than one long video of the whole talk. That is what makes the deck
forkable: a variant is an ordered subset of slides, and each slide brings its own
narration, so one deck is narrated the moment the other is. It also means a stale
slide costs one 40-second re-record, not a new take of everything.

### Files

| Path | What it is |
|---|---|
| `lib/colt_web/deck/slides.ex` | **The content.** Slide functions, per-variant order, narration scripts, the shared `d-*` stylesheet. |
| `lib/colt_web/live/deck_live.ex` | `/demo` — the player, and the closing slide's lead capture. |
| `lib/colt_web/live/admin/deck_studio_live.ex` | `/admin/deck` — the recorder and teleprompter. |
| `lib/colt_web/live/admin/demo_leads_live.ex` | `/admin/demo-leads` — what people chose at the end. |
| `lib/colt/resources/demo_lead.ex` | The submissions. |
| `lib/colt_web/components/funnel_thread.ex` | The reply composer's *Insert link* dropdown (§6). |
| `lib/colt/deck/manifest.ex` | `priv/deck/manifest.json` — the *only* record of what's recorded. |
| `lib/colt/deck/transcode.ex` | ffmpeg normalisation. Don't touch without reading §7. |
| `assets/js/deck.js` | `DeckPlayer` and `DeckRecorder` hooks. |
| `priv/static/media/deck/*.mp4` | The clips. Committed to git. |
| `test/colt_web/live/deck_studio_test.exs` | Smoke coverage for both surfaces. |

### Routes

- `/demo` — plays whichever variant `ab_funnel` assigned this visitor
- `/demo/features`, `/demo/solving_emails` — pin a variant, for linking a specific cut
- `/demo/<variant>?c=<campaign_contact_id>` — optional, see §6
- `/admin/deck`, `/admin/deck/:slide_key` — the studio (admin only)
- `/admin/demo-leads` — closing-slide submissions
- `/admin/ab` — the drop-off funnel

---

## 2. Editing a slide

Slides live in `slides.ex` between the `## ---------- features · cover ----------`
style banners. Each is a private function component returning the slide body:

```elixir
defp f_intro(assigns) do
  ~H"""
  <div class="d-pad flex flex-col justify-center h-full">
    <h2 class="d-h2">Kaks asja, ühes kohas.</h2>
    ...
  </div>
  """
end
```

Copy edits are just edits. Nothing else needs to change.

### Adding a slide

Five places, in this order:

1. Write the `defp <key>(assigns)` component.
2. Add `<key>` to `@features` and/or `@solving_emails` at the top of the module.
3. Add a `def title(:<key>), do: "…"` clause — the studio's slide-list label.
4. Add a `def script(:<key>), do: "…"` clause — the teleprompter text.
5. Add the `:<key> -> <key>(assigns)` line to `slide/1`'s dispatch.

Miss step 5 and it raises `CaseClauseError` at render. Miss step 3 or 4 and it
raises `FunctionClauseError`. There's no registry to keep in sync beyond these.

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

**Form controls therefore cannot live on a slide.** At slide scale a text input
renders around 13px on a laptop and less on a phone. The closing slide's buttons
are on the slide; the panel they open is rendered by `DeckLive` *outside*
`.deck-stage`, in ordinary `px`. Keep that split.

**Use the `d-*` classes**, defined in `Slides.styles/1`:

| Class | Use |
|---|---|
| `d-pad` | The slide's outer padding. Every slide's root div starts with it. |
| `d-h1` `d-h2` `d-h3` `d-h4` | Headings, 5.4 → 1.75cqw. **`d-h2` centres itself** — see below |
| `d-lead` `d-body` `d-fine` | Prose, 1.9 / 1.35 / 1.02cqw |
| `d-kicker` | The small uppercase label above a heading |
| `d-num` `d-num-sm` | Big tabular numbers |
| `d-card` `d-cardhead` | The bounded box and its header strip |
| `d-chip` `d-dot` `d-step-no` `d-avatar` | Small pieces |
| `d-x` | The red ✕ on a negative. Negatives are red on purpose — grey reads as "disabled" at slide distance |
| `d-inbox` | An email-address pill |
| `d-btn` | The CTA button |

Two shared components are worth knowing about before you reinvent them:

- **`fork/1`** — the left-to-right split used by `f_validate` and `f_reply`. It
  is a two-row grid of arrow glyphs sitting between the source box and a
  two-row column of branches; pass the same `gap` as the branch column and the
  arrows line up by grid arithmetic. An earlier CSS-border bracket had to guess
  where the column centres were and drifted whenever a gap changed.
- **`slider/1`** — a static picture of the campaign filter's dual-range control
  (`ColtWeb.Campaigns.FiltersLive.range_fset/1`). It exists so the filter slide
  shows the actual UI the viewer meets after registering. If that control gets
  restyled, restyle this too.

**Slide headings are centred, and content follows.** `d-h2` carries
`text-align: center` so every slide agrees. Most slide content is already
centred or full-width, but if yours is a narrow left-aligned column, centre it
too (`mx-auto`, or `text-center` on a trailing fine line) — a centred heading
over a left-hugging block reads as two layouts fighting, which is the exact
thing centring was meant to fix.

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
`countries` from the live database, so the filter slide's company count is true.
Prefer that over hardcoding when the figure exists.

---

## 4. The cover slide and the audio unlock

This is the single most fragile thing in the deck. Read it before touching the
cover or `deck.js`.

Browsers refuse to play audio that no user gesture asked for. The deck gets its
permission once, from the click on the cover's Play button, and every clip after
that rides on it. Two rules follow:

**The Play button must carry `data-deck-start`.** `DeckPlayer` listens for that
attribute at the document level and starts the video *inside the click's own
handler*. A `phx-click` round trip alone is far too late — by the time the server
replies the gesture is over.

**The cover has no narration of its own, so there is nothing to start.** That is
what `DeckPlayer.unlock()` exists for: it loads a clip onto the element and
plays it at zero volume for an instant, which is what marks the element as
user-started. It guards on the slide index, because if the server's advance
lands first the stray `pause()` would stop the deck the moment it began.

It prefers the next slide's clip (`data-next-src`, about to play anyway) and
falls back to *any* recorded clip in the deck (`data-any-src`). The fallback is
load-bearing: keyed off the next slide alone, a deck whose slide 2 isn't
recorded yet never unlocks, and the first clip that does exist plays silent.

If you make the cover recordable, or reorder so a non-cover slide is first, walk
through this path again. Symptom when it breaks: slide 2 onwards is silent, or
the console shows `NotAllowedError` from `play()`.

`Slides.cover?/1` is what marks these slides. `DeckLive` uses it to hold the deck
before the click, and to drop back into the un-started state if the viewer steps
back to slide 0.

---

## 5. Variants and the A/B test

`Slides.order/1` is the entire fork:

```elixir
@features       [:f_cover, :f_intro, :f_alternatives, :f_filter, :f_validate,
                 :f_contacts, :f_sending, :f_writing, :f_reply, :f_summary, :cta]
@solving_emails [:s_cover, :s_intro, :s_risk, :s_rules, :s_targeting,
                 :s_voice, :s_volume, :s_summary, :cta]
```

The two cuts are different **angles**, not different lengths: `features` walks
through the product, `solving_emails` sells the same product through
deliverability. `cta` closes both and is therefore recorded once.

Adding a variant is a new `order/1` branch plus an entry in `variants/0` and in
`Colt.ABVariants` — not a schema change.

Assignment comes from `ab_funnel`, which gives a visitor **one variant for the
whole site** (cookie, one year). So the same key that picks the deck also drives
whatever onboarding branches on later — it's one test, not two.

Tracking is already wired: one event per slide on first view (`slide_f_intro`,
`slide_s_risk`, …), plus `deck_started`, `deck_completed`, `cta_clicked` and
`lead_submitted`. `AbFunnel.AdminLive` at `/admin/ab` orders steps by average
position across visitors and counts unique visitors per step, so you get a
per-slide drop-off funnel grouped by variant for free. **Don't add bespoke
analytics** — add an `AbFunnel.track/3` call if something new needs measuring.

**Send people to bare `/demo`** — that is where the coin gets flipped. The
pinned URLs are for aiming a specific prospect at a specific cut.

**A pinned visit still counts, under the deck it played.** `AbFunnel.track/2`
reads `assigns.ab_funnel_variant` — the cookie — not the deck being shown, so
`DeckLive.mount` overwrites that assign with the resolved variant. Without it a
pinned visitor's slides are filed under whatever the cookie happened to say,
which files `slide_f_*` events under `solving_emails` and *corrupts* the funnel
rather than merely sitting outside it. `deck_started` carries `pinned: true|false`
so aimed traffic can still be told apart from the coin flip.

There is a test for exactly this (`a pinned deck logs its events under the
pinned variant`) — it sets a `solving_emails` cookie, opens `/demo/features`,
and asserts the recorded variant. Delete the assign and it fails.

Renaming a variant leaves old event rows carrying the old string, so `/admin/ab`
will show dead groups for a while. Returning visitors also keep the old value in
their year-long cookie; `order/1` falls through to `features` for anything it
doesn't recognise, so they see a real deck either way.

---

## 6. The closing slide

`cta` offers three choices, and all three write a `Colt.Resources.DemoLead` —
including "try it", which only navigates to `/register`. That row is the
denominator the other two are read against, so don't drop it.

- **`call_request`** and **`not_a_fit`** open a panel (name + phone, or a free
  text) rendered outside the stage. See §3.
- **`try_it`** records and navigates immediately.

Every submission pings Discord through `Colt.Services.Discord.Notify` and lands
in `/admin/demo-leads`.

**Two different links, don't confuse them:**

`visitor_id` and `variant` come from `ab_funnel` and are always present. They
join a lead back to the deck session that produced it — which cut, which slides,
where they dropped.

`campaign_contact_id` comes from an optional `?c=` param and is usually blank. It
only exists when the demo URL was handed to a specific contact rather than posted
cold. When set, the form prefills from that contact's person and the submission
is also mirrored as a `Note` on their thread, so it shows up in the conversation.

**Where those links come from:** the sales funnel's reply composer has an
*Insert link* dropdown, one entry per variant, each carrying the open contact's
id. `demo_links/1` in `SalesFunnelLive` builds them; `FunnelThread.composer`
renders them from its `insert_links` attr (empty by default, so the sending
funnel — same component — shows no button).

Insertion is deliberately client-side. The Trix wrapper is `phx-update="ignore"`,
so a server round trip would have nothing to patch; the option dispatches
`liid:insert-link` and the `TrixEditor` hook does the insert at the caret. The
hook then pushes `trix_input` immediately — LiveView otherwise only learns the
body on blur, and clicking Send straight after inserting would mail the version
without the link.

Automated sequence emails still don't carry these links: they're AI-written with
no placeholder substitution, and click tracking is Nylas-side, so there's no
href-rewriting hook to piggyback on.

The visitor has no actor, which is why the note goes through
`Note.create_system/2` rather than `Note.create/2`. The normal create carries
`change relate_actor(:author)`, and `relate_actor` defaults to
`allow_nil?: false` — with no actor it *errors* rather than leaving `author_id`
nil, and `authorize?: false` skips the policy but not the change. Reusing
`:create` here silently wrote no note at all.

`DemoLead` itself has policies: admin bypass, plus `submit` open to everyone.
Its text fields are length-bounded, because this is an unauthenticated write and
the app has no rate limiting — and once `?c=` is in play that text lands on a
real sales thread.

---

## 7. How narration is stored

**`priv/deck/manifest.json` is the only source of truth.** There is no database
table. Recording happens on a dev machine, so anything in Postgres would never
reach prod; the manifest is committed to git and ships with the repo.

```json
{"slides": {"f_intro": {
  "url": "/media/deck/f_intro-1785491570937.mp4",
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
(11s) so the deck is watchable before anything is recorded. Covers are excluded
from the runtime estimate, since they hold until clicked.

A clip that 404s or fails to decode never fires `ended`, and the dwell timer is
only armed for slides with *no* clip — so `DeckPlayer` also listens for `error`
and falls back to the dwell. Without it a broken file parks the deck on that
slide with only the manual arrows to escape.

---

## 8. Things that will bite you

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

**Pause does not stop the narration.** It stops the deck *advancing*; the clip on
the slide you're looking at plays to its end. That is why the decision lives in
`handle_event("advance", …)` and why `data-started` tracks `@started?` alone.
Wiring `paused?` into `data-started` looks like a fix and silently breaks manual
navigation, which pauses on purpose.

**Tests share `priv/` with the dev checkout.** `deck_studio_test.exs` snapshots
`manifest.json` and restores it in `on_exit`. Keep that helper — without it,
running the suite wipes real recordings.

---

## 9. Recording (what the human does)

`/admin/deck`, in a real browser with a camera. The studio shows the actual slide
so what's framed is what the prospect sees, with the slide's script underneath as
a teleprompter; the bubble preview appears only while recording, in the same
corner and shape as playback.

- Pick the deck (left) — a filter on the slide list, nothing more.
- The Runtime card under it is the sum of that deck's **recorded** clips, plus
  how many of its slides have one. Unrecorded slides contribute zero rather than
  the player's 11s dwell: it answers "how long is the talk I've got", not "how
  long does the deck sit on screen". Each option in the deck selector carries
  its own total, so you can compare cuts without switching.
- Space = record/stop, N = next slide.
- A slide has either a record button or its clip + Delete, never both. Replacing
  means deleting first.
- The device labels next to the button name the actual camera and mic. Check
  them — a stand-in stream looks identical to a real one until you read the label.
- Covers don't need a clip. They hold until Play is clicked either way.

Narrate **concepts, not layout**. "Iga vastus maandub siia" survives a redesign;
"vajuta sinist nuppu üleval paremal" doesn't.

---

## 10. Verifying a change

```bash
mix format && mix compile --warnings-as-errors
MIX_ENV=test mix test test/colt_web/live/deck_studio_test.exs
```

For visual changes, look at the slide — `/demo/features` and the studio render
the same component, so the studio is the faster loop.

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
