# Sales funnel — spec + phased build plan

> **Status: designed 2026-07-07, approved to build. Admin-only first, ⭐ golden** (destined to be
> revealed to normal users later — high-value, drive it to a releasable state). Supersedes the
> earlier brainstorm in `docs/closing-funnel.md`, which assumed hardcoded stages and one view.

The third funnel in Liid. The app now has three, and we name them distinctly to keep the
vocabulary clean (the word "pipeline" is deliberately avoided in code — it's ambiguous here):

1. **Enrichment funnel** — `/campaigns/:id/funnel` — validated contacts out of enrichment.
2. **Sending funnel** — `/campaigns/:id/ln` — the outbound send/reply machine.
3. **Sales funnel** — *this doc* — a lightweight personal CRM: interested contacts move by hand
   through user-defined stages (Interested → Demo → … → Won/Lost) while you keep talking to them.

## Locked decisions (2026-07-07)

- **Scope: per-campaign.** Each campaign has its own sales funnel and its own stage set. Sits as
  a **third nav section, "Sales"**, next to Enrichment/Sending.
- **Admin-only for now.** Section gated on `@current_user.is_admin`, rendered with the golden
  admin badge; LiveViews use `on_mount {ColtWeb.LiveUserAuth, :live_admin_required}`. Built as if
  for users — just hidden.
- **Customizable stages** → a `SalesStage` resource (data, not an enum), per campaign, reorderable.
- **Auto-entry.** When the sending machine marks a contact `:interested` **or `:call_ready`**, the
  contact auto-drops into the **first active stage** and a `StatusEvent` records the entry.
  (call_ready is included because a call-ready contact is definitionally ready for a sales
  conversation — veto in setup if unwanted.)
- **Unified feed** → a `StatusEvent` resource. Every status change — the new sales-stage moves
  **and** the existing sending transitions — writes one entry with actor (nullable = system),
  from/to, kind, and reason. Rendered inline in the thread timeline of both funnels.
- **StatusEvent approved** as the mechanism (not overloading free-text `Note`).

## Sales-workflow refinements (approved)

- **Won/Lost are outcomes, not columns.** `SalesStage.kind ∈ :active | :won | :lost`. The board
  shows active stages as the funnel; won/lost are exits. Enables a real conversion rate
  (won ÷ entered).
- **Days-in-stage** on every contact row (from the last stage-move `StatusEvent`, or entry time).
  The point of the board is catching a contact stuck in "Demo" for 30 days.
- **Lost reason.** Moving a contact to a `:lost` stage prompts for a short reason, stored on the
  `StatusEvent`. Reason is optional on other moves.

---

## Domain (new / changed Ash resources)

### `SalesStage` (new) — the customizable stages, per campaign
```
belongs_to :campaign
attrs:
  name (string, required)
  position (int, 0-based, ordering)
  kind (:active | :won | :lost, default :active)
  color (string, nullable — optional chip color)
identity :unique_position on [:campaign_id, :position]   (or reorder atomically)
```
- Actions: `list_for_campaign`, `create`, `rename`, `reposition`, `set_kind`, `destroy`,
  and `seed_defaults` (idempotent — inserts the starter set on first visit to the sales funnel).
- **Default seed** on first use of a campaign's sales funnel: `Interested (0)`, `Demo (1)`,
  `Proposal (2)`, `Won (kind :won)`, `Lost (kind :lost)`. Fully editable in the setup view.
- No `Ash.Query` outside the resource; code interface per project rules.

### `CampaignContact` (changed)
```
+ belongs_to :sales_stage, SalesStage   (nullable — null = not in the sales funnel yet)
+ update action :move_to_stage, args: [:sales_stage_id, :reason]
    - sets sales_stage_id; writes a StatusEvent (from old stage → new stage, actor = current user, reason)
+ update action :enter_sales_funnel, args: [:sales_stage_id]
    - idempotent; only sets sales_stage_id when currently nil; writes a system StatusEvent
```
The existing `status` machine is untouched — `sales_stage` is an orthogonal axis, exactly as the
old doc intended, just as an association instead of an enum.

### `StatusEvent` (new) — the unified feed entry
```
belongs_to :thread                       (same container the timeline already merges)
belongs_to :actor, Colt.Accounts.User    (nullable — null = system-generated)
attrs:
  kind (:sales_stage | :send_status | :reply_category | :entry, atom)
  from (string, nullable)                # human label of prior value
  to   (string, nullable)                # human label of new value
  reason (string, nullable)              # e.g. lost reason, or "classified as interested (0.92)"
  occurred_at (utc_datetime_usec, default now)
```
- Actions: `list_for_thread` (sort occurred_at asc), `record` (args: thread_id, kind, from, to,
  reason; `change relate_actor(:actor)` — actor is nil when called from a system/Oban context with
  `authorize?: false` and no actor).
- Policies: admin bypass + owner-of-campaign, mirroring `Note`.
- Rendered as a distinct timeline item (mono one-liner, actor + relative time, reason on a second
  line) — see the sending funnel's `timeline_item/1` note clause as the style reference.

### Feed wiring (write a `StatusEvent` from every transition)
A single helper (`Colt.Services.Sales.RecordStatusEvent` or inline in each action) called from:
- **Sales:** `move_to_stage`, `enter_sales_funnel`.
- **Sending (existing):** `mark_replied` (reply category), `manual_override`, `mark_bounced`,
  `mark_failed`, `skip`, `stop_sequence`, `approve`. Each maps to `kind: :send_status` /
  `:reply_category` with a readable from/to and, where available, a reason (e.g. the categorizer's
  label + confidence flows through `CategorizeReply`).
- These currently live in `campaign_contact.ex` actions + services under
  `lib/colt/services/sending/` (`manual_override.ex`, `stop_sequence.ex`, `categorize_reply.ex`).
  Wire the event write into those services / actions. Prefer a thread-scoped write so both funnels'
  timelines pick it up with no extra plumbing.

---

## Views

Both reuse the **sending funnel** layout (`ColtWeb.Sending.SendingFunnelLive` is the template to
clone — list+thread two-pane, URL-driven, mobile-collapsing). The enrichment funnel's table layout
is *not* the model here.

### Setup view — `/campaigns/:id/sales/setup`
Define the stages. Reorderable list of stage cards (drag or up/down), inline rename, add stage,
delete, and a per-stage `kind` control (active / won / lost). Calm-Pro boxes per `docs/design.md`.
On first visit, `seed_defaults` runs so the user starts from the starter set, not a blank slate.

### Sales funnel — `/campaigns/:id/sales[/:stage[/:contact_id]]`
Clone of the sending funnel:
- **Stage strip** on top = the campaign's `SalesStage`s in order (active stages, then won/lost
  exits visually separated). Each tile shows the stage name + live contact count. Click filters.
- **Left pane:** contacts in the selected stage. Row shows name, company, and **days-in-stage**
  (amber when stale). 
- **Right pane:** the existing thread view — timeline (emails + notes + **StatusEvents**), the
  Reply/Note composer, all reused as-is. Plus a **"Move to…"** control (stage dropdown) mirroring
  the sending funnel's "Mark as…" pattern; choosing a `:lost` stage prompts for a reason.

### Nav
Add a third `<.sidebar_section label="Sales">` in `lib/colt_web/components/liid.ex` after the
Sending section, gated `:if={@campaign && @current_user && @current_user.is_admin}`, golden badge.
Items: `Setup` (`:sales_setup`), `Sales funnel` (`:sales_funnel`). Add `nav_label/1` clauses, a
`sales_items_with_hrefs/1` + `sales_href/2`, and the routes in `router.ex`. LiveViews pass
`active={:sales_funnel | :sales_setup}` to `Layouts.app`.

---

## Phased build plan

Build top-to-bottom; each phase ships independently with acceptance bullets. Mark a phase
`✅ done` in this doc when its acceptance passes. Work on a `sales-funnel` branch; single-line
commits, no Claude attribution.

### Phase S1 — StatusEvent + feed wiring ✅ done
- `StatusEvent` resource + migration (`mix ash_postgres.generate_migrations status_events`).
- Write events from the **existing** sending transitions (mark_replied, manual_override,
  mark_bounced, mark_failed, skip, stop_sequence, approve) with readable from/to + reason.
- Render StatusEvents in the **existing sending funnel** timeline (add a 4th source to
  `build_timeline/3` + a `timeline_item/1` clause).
- **Acceptance**: reply to a test contact → the auto-categorization shows as a system feed line
  ("classified as interested") in the sending funnel thread, with time and reason; a manual
  "Mark as…" shows as an actor-attributed line.

### Phase S2 — SalesStage + setup view
- `SalesStage` resource + migration; `seed_defaults`; `CampaignContact.sales_stage_id` + migration.
- Setup LiveView (`/sales/setup`): list, add, rename, reorder, delete, set kind. Admin-gated.
- Third nav section "Sales" (admin, golden), routes.
- **Acceptance**: open `/sales/setup` on a campaign → starter stages seeded; rename/reorder/add a
  stage and mark one Won and one Lost; refresh persists. Section hidden for non-admin users.

### Phase S3 — Sales funnel view
- Clone `SendingFunnelLive` → `SalesFunnelLive`. Stage strip = `SalesStage`s with live counts.
  Left pane rows with days-in-stage. Right pane = reused thread view + composer + StatusEvents.
- **"Move to…"** control → `CampaignContact.move_to_stage` (writes a StatusEvent). Moving to a
  `:lost` stage prompts for a reason.
- **Acceptance**: a contact appears under its stage; move it Interested → Demo → the move shows in
  the feed with actor + time; move to Lost, enter a reason, see it recorded; counts update live.

### Phase S4 — Auto-entry + polish
- On `mark_replied(:interested)` and `:call_ready`, call `enter_sales_funnel(first_active_stage)`
  (idempotent) + system StatusEvent. Wire into `CategorizeReply` / `ManualOverride`.
- Empty states, conversion-rate tile (won ÷ entered), stale-in-stage styling, design pass vs
  `docs/design.md` and the sending-funnel demo.
- **Acceptance**: categorize a test reply as interested → contact auto-appears in the first sales
  stage with a system entry event; conversion tile computes correctly.

## Deferred (not v1)
- Cross-campaign board (per-campaign only for now).
- Any automation of movement (fully manual; AI integration follows later).
- Reveal to non-admin users (golden — later).
- Per-stage SLAs / reminders beyond the days-in-stage indicator.
