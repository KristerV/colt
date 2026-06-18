# Plan: just-in-time (pull-based) approval

> Standalone plan — written to survive a context reset. Pick this up cold.
> Builds on commit `baaf6a8` (variant-based A/B sending). The codebase already
> has: WriteLive (single-column writer + variant dropdown), VariantsLive
> scoreboard, SettingsLive (auto-approve + tracking + panic), per-variant
> learning, sidebar AUTO toggle.

## Context / why

Today auto-approve **commits everything up front**. The chain:
`IngestEnriched` bulk-promotes *all* enriched picks → `CampaignContact{:pending_approval}`,
and (if auto on) enqueues `AutoDraftAndApprove` per contact, which AI-writes the
sequence and **stamps `scheduled_at` on step 1 via `NextSlot`**. The send loop
(`SendDueEmails`, 60s cron) just sends rows whose `scheduled_at <= now`.

Problem: with 1000 contacts and 20/day capacity, all 1000 get drafted + approved +
date-stamped immediately. They're **committed** — changing or adding a variant
tomorrow affects nothing already drafted. You can't course-correct.

Also the manual flow needs a bulk **"Bring in N contacts"** button (the only caller
of `IngestEnriched.run`, in WriteLive's `promote` handler) before you can write.

## Target model

**The enriched pool is the queue. A `CampaignContact` is created only when something
pulls it — one at a time.** Two demand sources:

1. **Manual (Write):** opening Write / "next" mints **one** contact from the pool on
   demand, drafts it, you review. No bulk button.
2. **Auto:** each **open send slot** pulls one contact, drafts + sends it. Because a
   start is tied to a real free slot, **approval rate == send capacity automatically** —
   no buffer, no number to guess. Nothing is committed beyond contacts whose first
   email has actually gone out (follow-ups of started contacts stay committed — agreed).

## Current architecture (grounding, with paths)

- Enriched pool = `CampaignCompany` rows with non-null `picked_person_id`.
- `lib/colt/services/sending/ingest_enriched.ex` — bulk promote + `maybe_enqueue_auto`
  (gated on `campaign.auto_approve_on?`). Called only from WriteLive `promote`.
- `lib/colt_web/live/sending/write_live.ex` — `load_next_contact` uses
  `CampaignContact.next_pending`; `count_enriched_available/2` already computes
  "picks minus already-promoted person_ids" (reuse this to find the *next* candidate).
- `lib/colt/services/sending/auto_draft_and_approve.ex` — picks least-sent active+seeded
  variant, `EmailWriter.run`, approve, `schedule_step_one` via `NextSlot`, mark rest
  approved. **Reusable as the per-slot starter's worker.**
- `lib/colt/jobs/send_due_emails.ex` — 60s cron (`config/config.exs` crontab),
  `OutboundEmail.list_due(now, 200)` → enqueue `SendOne` per row.
- `lib/colt/services/sending/next_slot.ex` — stateless; given (account, not_before)
  returns next valid `scheduled_at` respecting per-(account,date) effective daily quota,
  burst cap (6–12), 1–5 min intra-burst, ≥60 min between bursts, working hours/tz.
- Capacity = sum of active `CampaignEmailAccount.daily_quota` (see capacity card in
  `sending_accounts_live.ex`).

## As built

Design settled on **sync-per-campaign**: there is no buffer to guess and no
slot-counting race, because each campaign's starts run serially in one job — every
contact's step-1 row is persisted before the next slot is evaluated, so `NextSlot`'s
today/tomorrow answer is always current.

1. **`PromoteOne` service** (`lib/colt/services/sending/promote_one.ex`): `run/2` fetches
   the next enriched candidate via `CampaignCompany.next_unpromoted/1` and promotes it →
   `{:ok, contact}` or `{:ok, :none}`. `promote_person/3` (dev email-rewrite + promote +
   Thread) is shared with `IngestEnriched`. Idempotent via `unique_per_campaign`.
   - `CampaignCompany.next_unpromoted(campaign_id)` — read action, `get? true,
     not_found_error?: false`. Filter: `picked_person_id` set and **`not exists`** a
     `CampaignContact` with the same `(campaign_id, person_id)` (unrelated-exists with
     `parent/1`). This is the anti-join done in the resource layer (no in-memory subtract).

2. **Write (manual)** (`write_live.ex`): `load_next_contact` → `next_or_mint/2`:
   `CampaignContact.next_pending`, else `PromoteOne.run`. Empty state only when the pool
   is exhausted. Bulk "Bring in N" button + `promote` handler + `count_enriched_available`
   removed.

3. **Auto starter** — two jobs:
   - `Colt.Jobs.AutoApproveDue` — **hourly** cron (`0 * * * *`). Lists
     `Campaign.list_auto_approve_active!` (auto on, not panicked) and enqueues one
     per-campaign job each. Light.
   - `Colt.Jobs.AutoApproveCampaign` — per campaign, on `:ai_writer`, **Oban-unique on
     `campaign_id`**, `max_attempts: 1`, runs **synchronously**. Guards (auto on, not
     panicked, ≥1 seeded active variant), then per healthy inbox loops while
     `NextSlot(inbox, now, step_position: 0)` lands **today**: pull next contact
     (`next_pending` first, else `PromoteOne`), `AutoDraftAndApprove.run(id, inbox_id:)`.
     Stops on tomorrow-slot (inbox full), `:none` (pool empty), error, or a per-inbox
     guard (200). `slot_today?` compares local dates in the inbox tz.
   - **Instant fill:** flipping auto-approve on in Settings enqueues the per-campaign job
     immediately (settings_live.ex), so the schedule fills without waiting an hour.

4. **`AutoDraftAndApprove`**: added `inbox_id:` opt (pins the inbox the slot was counted
   against — fixes the AssignInbox mismatch) and a `:pending_approval` status guard
   (returns `{:ok, :skipped}` if already started — backstop for the manual+auto edge).

5. **`IngestEnriched`**: dropped `maybe_enqueue_auto`; now a thin dev/admin bulk wrapper
   over `PromoteOne.promote_person`. The orphaned `Colt.Jobs.AutoDraftAndApprove` worker
   (per-contact, was enqueued by `maybe_enqueue_auto`) was deleted — the sync starter
   calls the service directly.

## Existing-data caveat (koristaja, the live client campaign)

koristaja has 28 `:pending_approval` contacts (bulk-promoted earlier); its enriched pool
is currently fully promoted (35 picks = 35 contacts, so `next_unpromoted` → `nil`). **No
migration** — Write's `next_pending` and the starter both drain existing pending first,
then mint from the pool. (Verified: `next_unpromoted` returns `{:ok, nil}` and
`PromoteOne.run` returns `{:ok, :none}` on the exhausted pool.)

## Verification

- ✅ `next_unpromoted` anti-join returns the right candidate / `nil` against live data.
- ✅ `AutoApproveCampaign.perform` returns `{:ok, :inactive}` with auto off (guards run,
  no crash). Today-gate resolves: koristaja's 1 healthy inbox (quota 15) → next slot today.
- ⬜ Auto on, tiny quota (e.g. 3/day) → exactly ~3 drafted+scheduled today, rest stay
  un-promoted; count(approved-but-unsent) ≈ today's remaining capacity, NOT the whole pool.
  **(Not run — live paying client; flip on only with a tiny quota.)**
- ⬜ Change a variant mid-run → next slots use the new least-sent one.
- Drive in browser (Playwright MCP; chromium symlink at `/opt/google/chrome/chrome`):
  log in via magic link from `/dev/mailbox`, campaign `koristaja` =
  `6210fbef-a16d-4726-9ca2-e4b335a4193e`.

## Risks / notes

- **Live sending for a paying client** — built with auto OFF; test with a tiny quota
  before enabling.
- Concurrency double-pull is **eliminated**: one Oban-unique job per campaign = serial
  within a campaign. `PromoteOne`'s identity upsert is now just a backstop.
- `NextSlot` today/tomorrow gate **verified** as the capacity signal — no
  `slots_remaining_today` helper needed (the sync loop keeps the row count current).
- Bounded overshoot is **not** a concern in the sync model (it was only a risk under the
  earlier async-enqueue design).
