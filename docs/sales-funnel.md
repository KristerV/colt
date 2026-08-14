# Sales funnel — spec

> **Status: rebuilt 2026-08-09** as a date-driven work queue. Supersedes the original
> stage-based build (2026-07-07), which is described at the bottom under *History*.
> Admin-only, ⭐ **golden** (destined to be revealed to normal users later — high-value, drive it
> to a releasable state).

The third funnel in Liid. The app has three, and we name them distinctly to keep the vocabulary
clean (the word "pipeline" is deliberately avoided in code — it's ambiguous here):

1. **Enrichment funnel** — `/campaigns/:id/funnel` — validated contacts out of enrichment.
2. **Sending funnel** — `/campaigns/:id/sending-funnel` — the outbound send/reply machine.
3. **Sales funnel** — *this doc* — a lightweight personal CRM for the people you're talking to.

## The problem this shape solves

The first build let each campaign define its own stages (`Interested → Demo → Proposal → Won →
Lost`) and made those stages the board's columns. Two things were wrong:

1. **The custom stages weren't stages, they were a todo list.** "Demo booked" and "Proposal sent"
   are things you tick off, not mutually exclusive states. Forcing them into columns meant a
   contact could only be in one at a time, and Won/Lost had to be jammed into the same list to
   make the board work at all.
2. **A status board can't answer "who needs me today?"** Nothing carried a date, so
   days-in-stage was the only time signal and you still had to read every row to find the work.

## The model

**The columns are derived from a date, never typed.** Exactly two things are set by hand:

| field | meaning |
|---|---|
| `next_action_at` | when to next touch this contact |
| `outcome` | `:won` / `:lost`, or `nil` while open |

Everything else falls out, via
`Colt.Resources.CampaignContact.Calculations.SalesBucket`:

| bucket | derivation |
|---|---|
| **Now** | no outcome, and `next_action_at` is null (never triaged) or falls **on or before today** |
| **Later** | no outcome, and `next_action_at` falls on a day **after** today |
| **Won** / **Lost** | `outcome` is set |

A contact with no date at all lands in **Now** on purpose — untriaged is loud, not invisible.

The boundary is a **calendar day, not a timestamp**: something dated today is work for today, so
it belongs in Now from midnight. `Colt.Sales.Clock` owns that — it resolves "today" in
`Europe/Tallinn` and is the single place the board's chips and the bucket calculation both go
through, so they can't disagree. Presets store 09:00 local, converted to UTC.

Prior art this borrows from: **Pipedrive's** activity-based selling (every deal carries a dated
next activity; the board colours by it, and "no activity scheduled" is the loudest state),
**Front/Superhuman/Close** snoozing, and **Todoist/Things** Today-vs-Upcoming.

## Locked decisions

- **Scope: per-campaign.** Each campaign has its own funnel and its own checklist.
- **Admin-only for now.** `on_mount {ColtWeb.LiveUserAuth, :live_admin_required}` + golden badge.
  Built as if for users, just hidden.
- **Auto-entry.** When the sending machine marks a contact `:interested` **or `:call_ready`**,
  the contact enters the funnel with no date — i.e. straight into **Now**, awaiting triage — and
  a `StatusEvent` records the entry. `Colt.Services.Sales.AutoEnter`'s `@triggers` is the single
  toggle.
- **A reply pops the contact back into Now.** You park someone until Tuesday, they answer on
  Monday — the date is stale the moment their reply lands, so
  `Colt.Services.Sales.ReactivateOnReply` clears `next_action_at` and the feed entry says
  "prospect replied". It runs from `CategorizeReply`'s real-reply branch, so it covers every
  category a human has to answer (`:interested`, `:not_interested`, `:other`) but never `:ooo`,
  which isn't a reply. Guarded to contacts in the funnel, still open, and actually holding a
  date — a Won/Lost contact stays closed, and reopening is a human's call.
- **Unified feed** → `StatusEvent`. Sales writes `:next_action`, `:outcome` and `:checklist`;
  the sending machine writes `:send_status` / `:reply_category`; entry writes `:entry`.
  `:sales_stage` is retained **read-only** so pre-2026-08-09 rows still render.
- **Lost reason** is prompted when marking a contact lost, and stored on both the contact
  (`outcome_reason`) and the feed entry.
- **No conversion-rate tile.** It was dropped 2026-08-09 — a percentage is a reporting number,
  and this view is a work queue. `list_entered_for_campaign` went with it, since its filter
  duplicated `list_for_sales_funnel` and the tile was its only caller.

## Checklist

The campaign-level list of things you do with every contact — **not** stages and **not**
statuses. A contact ticks them off in any order, in their thread; ticking has no effect on which
bucket they're in.

- `Colt.Resources.ChecklistItem` — per campaign, `name` + `position`, reorderable.
- `Colt.Resources.ContactChecklistItem` — one contact's tick. **Created lazily**, only when an
  item is first ticked, so the thread view renders the campaign checklist and looks up done-state
  by `checklist_item_id`. Editing the campaign checklist needs no backfill and no materialisation
  step.
- `checklist_item_id` is nullable, with a `name` alongside it, to leave room for ad-hoc
  contact-specific todos. Nothing creates those yet.
- **Nothing is seeded on mount.** The checklist is optional, and an on-visit seed would
  resurrect the starter set every time someone cleared it deliberately. The empty state offers
  `SeedChecklist` as a button instead.

## Views

### Checklist — `/campaigns/:id/sales/checklist`
`ColtWeb.Sales.ChecklistLive`. Reorderable cards: inline rename (debounced, patched in memory so
the focused input isn't re-rendered), up/down adjacent-position swap, add, delete. Empty state
offers the starter checklist.

### Sales funnel — `/campaigns/:id/sales[/:bucket[/:contact_id]]`
`ColtWeb.Sales.SalesFunnelLive`, slugs `now | later | won | lost`. Same list+thread two-pane as
the sending funnel, URL-driven, mobile-collapsing.

- **Bucket strip**: four flush tiles in one segmented block (`gap-px` over a border-coloured
  background draws the hairlines, so the 2×2 mobile grid and the desktop row need no per-edge
  border rules). One `list_for_sales_funnel` query feeds both the counts and the lists; contacts
  are grouped by `:sales_bucket` in Elixir, so there are no per-bucket round trips.
- **Left pane**: rows with a date chip — `4d overdue` (amber), `Today` (accent), `No date`,
  `in 3d`, or the outcome date for closed contacts. Open buckets sort most-overdue-first with
  undated rows last; Won/Lost sort most-recently-closed first.
- **Right pane**: the shared `FunnelThread.thread_pane`, shaped exactly like the contact list —
  one bounded card, a `flex-none` header, a `flex-1 overflow-y-auto` body holding the timeline and
  composer. (It omits the list's `overflow-hidden`, since the header's disclosures hang below it
  and would be clipped; the body rounds its own bottom corners instead.) The body carries the
  `ThreadScroll` hook, keyed `thread-scroll-<contact_id>` so switching contacts remounts it and
  lands on the newest message; on later updates it only follows if you were already within 120px
  of the bottom, so a checklist tick can't yank you out of a thread you're reading.

  There is no contact header card and no checklist card: the header *is* the contact UI, and the
  detail collapses into disclosures, because it's reference material you consult occasionally
  rather than something worth a permanent card above every thread. Four zones:

  | zone | closed | open |
  |---|---|---|
  | contact name | name | panel with title, email, phone, company, registry + website links, and the `:info_actions` slot (Edit) |
  | checklist | next unticked item + `1/3` | all items as checkboxes |
  | outcome | `Outcome` / `Won` / `Lost` | Won · Lost, or Reopen once closed |
  | next action | `Next action` / `Due today` / `in 3d` / `2d overdue` | Tomorrow · In 3 days · Next week · In 2 weeks · date picker · Clear |

  Presets resolve server-side, so they mean days in the funnel's timezone rather than the
  browser's. Marking Lost opens the reason modal. Closing clears `next_action_at`, so a reopened
  contact returns to Now rather than to a stale date, and the next-action control is hidden while
  closed rather than offering to schedule work on a finished deal.

  Three slots carry what differs per funnel: `:actions` (right-hand controls), `:bar_items`
  (middle — the sales checklist), `:info_actions` (inside the name disclosure). The sending funnel
  passes only `:actions`, so it gets the same collapsed contact card for free and nothing else
  changes.

### Nav
`<.sidebar_section label="Sales">` in `lib/colt_web/components/liid.ex`, gated on
`@current_user.is_admin`, golden badge. Items: `Checklist` (`:sales_checklist`), `Sales funnel`
(`:sales_funnel`).

## Deferred

- **Ad-hoc per-contact todos** — the columns exist; no UI.
- **Cross-campaign Now queue** — the real end state once several campaigns run at once. `/search`
  is the precedent for a workspace-level route, and `sidebar_section`'s unused
  `variant: :workspace` branch is a free slot.
- Notifications / a daily digest when something enters Now.
- Reveal to non-admin users (golden — later).

## History

The original 2026-07-07 build shipped a `SalesStage` resource (per-campaign, reorderable, with
`kind ∈ :active | :won | :lost`) and made those stages the board's columns, with a
days-in-stage indicator and a "Move to…" control. The 2026-08-09 migration
(`20260809110928_sales_checklist_and_next_action.exs`) renamed `sales_stages` into
`checklist_items`, copied each contact's won/lost stage onto the new `outcome` column before
dropping `sales_stage_id`, and deleted the Won/Lost stage rows. Contacts that had been sitting
in an active stage came across with no outcome and no date — i.e. into Now, correctly, since
none of them had ever been given a next action.
