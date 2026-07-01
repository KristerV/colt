# Closing funnel (sales pipeline) — design intent, not yet built

> **Status: designed 2026-06-22, not built.** Captured here so it can be built fast when
> needed. No `PipelineLive`, no `pipeline_stage` attribute, no `:in_convo`/`:won`/`:lost`
> exist in the codebase yet.

> ⭐ **Golden admin feature.** This ships **admin-only first** (just for the founder), but it
> is destined to be revealed to normal users later. That makes it high-value — the kind of
> thing to focus on and get to a releasable state. When building admin-gated features, assume
> they may go public and flag them as such so we know where to invest. See the convention note
> at the bottom.

## The brief (user, verbatim)

> "i need one more section after enrichment and sending emails. and that's closing the sale.
> but this is just for me, so only admin has access for now. but yeah add another section,
> although i think it's just one more view. so all contacts who are interested end up in here
> and it's another funnel with **interested → in convo → lost → won**. i actually have not
> thought this out, i don't know much about sales. i just want a pipeline to keep an eye on
> the people i'm talking to. and the view is almost identical to the sending emails one, i
> just want to send more emails and write notes for when i call them."

So: a lightweight, personal CRM pipeline. One extra view. Not a full sales suite.

## What already exists that we reuse (verified against the code)

- **Sending funnel is the exact template.** `ColtWeb.Sending.SendingFunnelLive`
  (`lib/colt_web/live/sending/sending_funnel_live.ex`) — bucket strip at top → drill into a
  bucket → contact list + thread detail pane, all URL-driven with back-button support, mobile
  collapses to one level. The enrichment funnel (`ColtWeb.Campaigns.FunnelLive`) is the same
  pattern and also a reference.
- **Thread / Notes / compose already power "send a reply + write a note"** on a contact
  (`SendManualReply`, `Note`, `Thread`, `Email`). The pipeline view gets all of this for
  free — same thread, same note timeline, same compose box. "Send more emails + write call
  notes" needs **no new plumbing**.
- **"Interested" already exists as a signal**: `CampaignContact.reply_category == :interested`
  (there's also a `:call_ready` status). That's the entry condition into this funnel.
- **Admin gating is a one-liner**: `on_mount {ColtWeb.LiveUserAuth, :live_admin_required}`.

## Proposed shape

A new admin-only **`PipelineLive`** that is basically the sending funnel with different
buckets.

- Add a **`pipeline_stage`** enum on `CampaignContact` — `:interested → :in_convo → :lost →
  :won` — **orthogonal to the existing `status`** (status tracks the send/reply machine;
  pipeline_stage tracks the human sales conversation).
- Contacts enter at `:interested` when `reply_category` becomes `:interested` (and/or
  `:call_ready`). Decide the exact entry trigger at build time.
- The bucket strip = the four stages. Click a stage → contact list → thread/notes/compose pane
  reused as-is.
- **Move a contact between stages** with buttons in the detail pane, mirroring the existing
  `mark_as` manual-override pattern in the sending funnel.
- Route alongside the others, e.g. `/campaigns/:id/pipeline[/:stage[/:contact_id]]`.

## Open decisions (deferred — the original convo was interrupted here)

The design discussion stopped before these were answered. Resolve when building:

1. **Entry trigger** — auto-move to `:interested` on `reply_category: :interested`, or only on
   an explicit user action? (`:call_ready` too?)
2. **Scope** — per-campaign pipeline, or one cross-campaign pipeline for everyone the founder
   is talking to? The brief ("keep an eye on the people i'm talking to") leans cross-campaign.
3. **Terminal stages** — do `:won`/`:lost` do anything beyond bucketing (e.g. stop any residual
   automation, timestamp)?
4. **Whether `pipeline_stage` should also short-circuit any remaining sending** for that
   contact once they're in the pipeline.

## Effort estimate

Small. It's a clone of an existing LiveView + one enum attribute + a handful of stage-move
events. Most of the surface area (threads, notes, compose, two-pane layout, mobile collapse)
already exists.

---

## Convention: "golden" admin features

Features we build **admin-only first but intend to reveal to normal users later** are golden —
prioritize them and drive them to a releasable state, because the eventual payoff is a shipped
user-facing feature, not just internal tooling. When adding an admin-gated feature, note in its
doc whether it's destined to go public so we know where to focus.
