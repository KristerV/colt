# Email sending

The second half of Liid. Enrichment produces validated contacts; this feature turns those contacts into approved, scheduled, AI-drafted outbound sequences with replies funneled back into a thread view and a stats funnel.

This document is **both** the spec and the phased build plan for the feature. It supersedes nothing in `docs/spec.md` (that doc remains canonical for the enrichment half).

---

## 0. Decisions already taken

These were confirmed before drafting:

- **Provider**: **Nylas v3, EU region**. Unified API for Google Workspace / Microsoft 365 / generic IMAP+SMTP, native threading (`thread_id`), hosted OAuth, bounce + delivery events, public DPA, SOC 2 Type II, ISO 27001, EU data storage. Base URL `https://api.eu.nylas.com/v3`.
- **Inbox routing**: sticky per contact. On approval a `CampaignContact` is bound to one `EmailAccount`; every step + followup for that contact ships from that inbox.
- **Auto-approve**: disabled by default. Becomes *available* (toggle appears in campaign settings) after the user has accepted 10 AI-drafted sequences without modifying any subject or body. Counter is per-campaign, not global. Once unlocked the user flips it on/off manually.
- **AI language**: per-campaign setting, defaults to English in v1. User picks per campaign in the sequence view. Applies to every generated subject + body in the campaign.
- **Sequence edits after start**: allowed. Applies to *new contacts only* — in-flight contacts continue running on the sequence snapshot they were approved with.
- **Email accounts in navigation**: global per user. The per-campaign "Sending accounts" view picks from the global library and sets quotas.
- **Sending hours**: Mon–Fri 09:00–17:00 in the inbox's TZ. Followups that would land outside slide forward to the next open window. No holidays handled in v1.
- **Open/click tracking**: off by default, per-campaign toggle. Requires a configured tracking domain on the Nylas side; UI shows the CNAME setup if the toggle is flipped on.

## 1. Working assumptions (correct before phase 1)

Decisions I made without asking. Skim, push back where wrong.

1. **`CampaignContact` is a new resource** joining `Campaign` ↔ `Person`. Distinct from the existing `CampaignCompany`. A contact in two campaigns has two rows.
2. **Sequence is per-campaign**, designed once, applied to every contact in that campaign. On approval of a contact, the current sequence is **snapshotted** onto the `CampaignContact` (jsonb `sequence_steps`) so future sequence edits don't disturb in-flight rows.
3. **Approval is per contact, all-steps at once** — user reviews subject + body for each step in the contact's sequence and clicks one "Approve" button. No per-step approval.
4. **Subject is also AI-drafted and also versioned** (`ai_subject`, `user_subject`). The auto-approve "clean" check is `user_subject == nil and user_body == nil` — the user-fields are only populated when the user actually edits, so a nil pair means they accepted the AI version unchanged.
5. **Daily quota is a ceiling on total sends** (new + followups), stored **globally on `EmailAccount.daily_quota`** (not per-campaign — confirmed E2). The scheduler is FCFS into burst slots — every `Email` getting scheduled (whether a fresh approval or a followup falling due) gets the next available burst slot, and once the day's effective cap for that inbox is reached, further sends roll to tomorrow's first burst. We don't try to prioritize followups over new sends or vice versa; it sorts itself out by scheduling time. UI says: *"X emails/day from this inbox, including followups."*
6. **Effective daily send count varies ±**: `effective = round(quota × uniform(0.85, 1.05))`, recomputed daily per inbox.
7. **24h dedupe** is hardcoded at send-time. Recipient address + campaign id checked against `emails` table for any send in the last 24h. Violation **raises** (Oban job dies, logs, alerts via Sentry-equivalent — whatever the project already has). Never silently skip.
8. **Threading model**: one `Thread` per `CampaignContact`. `Email belongs_to Thread`, `Note belongs_to Thread`. `Thread` is the polymorphic container; in v1 only emails + notes attach.
9. **Cross-domain replies**: trust Nylas's `thread_id` first. If a brand-new inbound message arrives with no matching thread but the sender domain == an active contact's email domain in the same inbox, attach it to that contact's most recent thread. UI flags the auto-attached message subtly so the user can detach if wrong.
10. **Reply categorizer model**: Claude 4.5 Sonnet via the existing OpenRouter pipeline. Categories: `:ooo | :interested | :not_interested | :other`. Any category halts the sequence; "other" surfaces a manual-review badge.
11. **AI writer model**: Claude 4.5 Sonnet. Few-shot examples drawn from previous `Email` rows in the same campaign where `user_*` is non-nil (i.e. the user edited the AI draft). **No ranking** — all qualifying examples are passed (cap 20 to keep prompt size sane). Each example carries `{before_ai, after_user, company_brief, person_brief}` so the model can match on both company shape and job title. **A/B selection**: the prompt also includes a procedurally generated integer 0–99; the model is instructed to pick which example (if any) to draw on using that integer as a deterministic seed, so multiple distinct example "styles" get sampled across contacts instead of the model always falling onto one.
12. **Bounce threshold**: a single campaign-level rule. After ≥50 sends in the campaign, if `bounce_rate > 5%`, flip `panic_switch_on = true`. No per-inbox pause logic in v1; the campaign-wide halt is the only stop.
13. **Subscription/billing view**: render a placeholder card with "Plans coming soon", a disabled "Choose plan" button, and a link to mailto support. No logic.
14. **Demo inbox** lives next to the subject field in the writing view. Renders a fake Gmail-style list of 8 surrounding subjects (fixed seeded sample) with the user's subject inserted at row 4. Pure presentational; no interaction.
15. **Polling, not webhooks (v1)**: Nylas exposes both `message.created` webhooks and a `GET /v3/grants/{grant_id}/messages?received_after=…` list endpoint. Webhooks are unreliable across deploys (events fired while we're down are dropped unless retried, depends on provider). Polling is simpler, idempotent, and survives restarts: one cron worker every 30s asks each healthy `EmailAccount` for messages since `last_sync_at`. Webhooks deferred to a later phase if latency matters. **Outbound** still uses Nylas's send endpoint synchronously inside the Oban send job.
16. **Inbox connect = hosted flow**: we don't render our own OAuth screens. `/email-accounts` has "Connect Gmail / Outlook / IMAP" buttons that redirect to Nylas's hosted auth page; Nylas bounces back to a callback URL with the new `nylas_grant_id`. We persist, done.
17. **AI writes per contact, just-in-time**: drafts are generated when the user *opens* a contact in the writing view, not in bulk at promotion time. This is what makes the learning loop tight — the writer for contact N sees every edit the user made through contact N-1. Auto-approve mode is the exception: when on, drafts are pre-generated by an Oban worker so contacts go straight to `:approved` without UI.
18. **Promotion is a button, not automatic**: a "Bring in enriched contacts" action on the writing view that, in one transaction, inserts a `CampaignContact{status: :pending_approval}` for every `CampaignCompany` with a non-null `picked_person_id` that doesn't already have a contact row. No per-person job. Re-clickable any time new enrichments land.

---

## 2. Provider integration — Nylas

Reference: <https://developer.nylas.com/docs/v3/>. Re-verify endpoints and shapes against current docs before writing the client; this section captures the **contract we depend on**, not the source of truth. **Use the EU region** (`api.eu.nylas.com`) — required for our GDPR posture; locks data storage to EU.

Nylas v3 terminology: a connected mailbox is a **grant** with a `grant_id`. All message/thread endpoints scope by grant.

| Concern | How we use Nylas v3 |
|---|---|
| Account connect | Hosted auth at `/v3/connect/auth` (Google, M365, IMAP). On callback Nylas returns a `grant_id`. We never see or store the user's OAuth tokens — Nylas holds them. |
| Send | `POST /v3/grants/{grant_id}/messages/send` with `to`, `subject`, `body`, `reply_to_message_id` for followups. Response includes `id` (message id) and `thread_id`. |
| List inbounds | `GET /v3/grants/{grant_id}/messages?received_after={unix_ts}&in=INBOX` — used by `PollInbounds`. |
| Bounces | Per Nylas v3 docs: bounce notifications surface as messages from MAILER-DAEMON / postmaster with a `tracking.bounced` flag (verify exact field at implementation time). We detect during ingestion. |
| Tracking | Per-send `tracking_options: {opens, links}`. Requires a verified custom domain on the Nylas dashboard when on (one shared, per §12). |
| Cross-domain reply | Nylas computes `thread_id` from RFC headers (Message-ID/References/In-Reply-To) so cross-domain replies in the same thread arrive with the same `thread_id`. No work on our side beyond storing it. |

**Credentials**: `NYLAS_CLIENT_ID`, `NYLAS_API_KEY` (server-side admin key), `NYLAS_API_URI = "https://api.eu.nylas.com"`. `NYLAS_WEBHOOK_SECRET` reserved for a future webhook phase but not yet used. All in `runtime.exs`. Per project convention: `fetch_env!` in prod, tolerant in dev.

**Client module**: `Colt.Nylas` with one function per endpoint. Returns `{:ok, _} | {:error, _}`. No HTTP calls inline in Oban jobs or LiveViews.

---

## 3. Domain (Ash resources)

### New resources

```
EmailAccount                                      # one per connected inbox, scoped to User
  belongs_to :user
  identity :nylas_grant on [:nylas_grant_id]
  attrs: provider (:google | :m365 | :imap),
         address, display_name,
         nylas_grant_id,                          # Nylas v3 holds the OAuth tokens; we only store the grant_id
         tz (default "Europe/Tallinn"),
         daily_quota (int, default 15),            # global per inbox; same ceiling across every campaign this inbox is in
         status (:healthy | :paused_bounces | :disconnected | :auth_error),
         last_sync_at, paused_reason

Sequence                                          # one per Campaign
  belongs_to :campaign
  attrs: language (e.g. "et", "en"), version (int, incremented on structural edit)
  has_many :sequence_steps

SequenceStep
  belongs_to :sequence
  attrs:
    position (int, 0-based),
    kind (:email | :terminal),
    delay_days (int, default 2 — wait BEFORE this step fires, relative to prior step's send_at; for the terminal step this is days after the final email),
    terminal_action (:no_reply | :call_ready | nil)   # only set when kind == :terminal
  # Sequence always ends with exactly one :terminal step. The editor enforces that.

CampaignContact                                   # join: Campaign × Person
  belongs_to :campaign
  belongs_to :person                              # = the picked_person from CampaignCompany
  belongs_to :assigned_email_account, EmailAccount
  belongs_to :thread, Thread
  identity :unique_per_campaign on [:campaign_id, :person_id]
  attrs:
    status (:pending_approval | :approved | :sending | :replied
            | :call_ready | :no_reply | :bounced | :failed),
    sequence_snapshot (jsonb — full step list frozen at approval time),
    sequence_version (int — matches Sequence.version at approval),
    reply_category (:ooo | :interested | :not_interested | :other | nil),
    auto_approved? (bool, default false),
    approved_at, completed_at

Thread                                            # one per CampaignContact (v1)
  belongs_to :campaign_contact
  attrs: nylas_thread_id (nullable until first send),
         last_activity_at, manual_status_override (nullable)
  has_many :emails
  has_many :notes

Email
  belongs_to :thread
  belongs_to :email_account                       # which inbox sent/received it
  attrs:
    direction (:outbound | :inbound),
    step_position (int, nil for inbound and manual replies),
    ai_subject, ai_body,                          # always set on draft
    user_subject, user_body,                      # nil unless user edited; effective = user_? || ai_?
    is_manual_reply (bool, default false),        # rich-text manual reply from thread view
    status (:drafted | :approved | :scheduled | :sent | :bounced | :failed | :skipped),
    scheduled_at, sent_at,
    nylas_message_id, nylas_thread_id,
    reply_category (inbound only),
    bounce_reason

Note
  belongs_to :thread
  belongs_to :author, User
  attrs: body (text), inserted_at

CampaignEmailAccount                              # per-campaign enrollment of an EmailAccount
  belongs_to :campaign
  belongs_to :email_account
  identity on [:campaign_id, :email_account_id]
  attrs: paused? (bool, default false),
         paused_reason
  # Quota lives on EmailAccount.daily_quota — global per inbox, not per campaign.

Campaign (additional attrs, inlined — no separate settings resource)
  sending_initialized? (bool, default false)        # flipped when user first lands on /sequence
  panic_switch_on (bool, default false)
  auto_approve_unlocked? (bool, default false)
  auto_approve_on? (bool, default false)
  auto_approve_streak (int, default 0)              # cumulative untouched approvals, threshold 10
  tracking_opens? (bool, default false)
  tracking_clicks? (bool, default false)
  tracking_domain (string, nullable)
```

### Conventions
- All resources follow `default_accept` + named actions per project rules.
- No `Ash.Query` outside resources; everything goes through a defined action with code interface.
- Identities used for all unique constraints (no raw Ecto unique index calls).
- Polymorphic note/email design deferred — for v1 they share a `Thread` parent but are distinct resources.

### Mutations from enrichment → sending
**Manual, user-triggered.** The writing view has a "Bring in enriched contacts" button. Clicking it runs `Colt.Services.Sending.IngestEnriched` once: in a single transaction it inserts a `CampaignContact{status: :pending_approval}` for every `CampaignCompany` in this campaign whose `picked_person_id` is set and which doesn't already have a `CampaignContact`. No per-person Oban job; no AI calls happen here — drafting is just-in-time when the user opens a contact (§4.3).

The button shows a count: *"Bring in 23 enriched contacts"*. After click, the writing flow auto-advances to the first one.

---

## 4. Navigation & views

Inside a campaign, replace the current top-strip stepper with a **left sidebar** (≈ 240px):

```
ENRICHMENT
  · ICP
  · Market
  · Filters
  · Target
  · Funnel                          (current /campaigns/:id/funnel)

SENDING
  · Sequence                        (/campaigns/:id/sequence)
  · Sending accounts                (/campaigns/:id/sending-accounts)
  · Writing                         (/campaigns/:id/writing) — approval queue
  · Funnel                          (/campaigns/:id/sending-funnel)

─────
ACCOUNT
  · Email accounts                  (/email-accounts) — global, user-scoped
  · Billing                         (/billing) — placeholder
```

Sections collapse but expanded by default. Active item is ink-on-paperAlt with 2px left bar. Mono uppercase section labels.

### 4.1 Sequence view (`/campaigns/:id/sequence`)

Block-style visual editor. Each block is a 2px-radius card on paper background with hairline divider. From top to bottom:

```
┌─ Step 1 · Initial ────────────────┐
│ Email                             │
└───────────────────────────────────┘
       ↓ wait 2 days
┌─ Step 2 · Followup 1 ─────────────┐
│ Email                             │
└───────────────────────────────────┘
       ↓ wait 2 days
┌─ Step 3 · Followup 2 ─────────────┐
│ Email                             │
└───────────────────────────────────┘
       ↓ wait 2 days
┌─ Terminal ────────────────────────┐
│ Mark as [no_reply ▾]              │
└───────────────────────────────────┘
```

- "Wait N days" rows are inline editors (number input + "days" suffix, default 2).
- Add/remove followups via + button between blocks and × on each block.
- Terminal row: dropdown `Mark as no_reply | Ready for call`, plus its own "wait N days after final email".
- Below the editor: **"Language"** select (default Estonian for EE), and a **"Tracking"** section with two checkboxes (Opens / Clicks) and the custom-domain instructions when either is on.
- Save is implicit on blur. Version is incremented on any structural change (steps add/remove/reorder, terminal action change). Delay edits do *not* increment version (they apply to next-drafted contact only and we don't need a snapshot bump).

### 4.2 Sending accounts view (`/campaigns/:id/sending-accounts`)

Two modes (per design prototype):

- **Default** (`/campaigns/:id/sending-accounts`) — table of inboxes currently enrolled for this campaign, with per-row stats (sent, reply%, bounce%, status) and a `remove` button. Header `+ Add accounts` button navigates to picker mode. Below the table: live-computed capacity card — *"At full capacity this campaign sends ~N emails/day, ~Nk/month. A single contact takes Y days to complete."*
- **Picker** (`/campaigns/:id/sending-accounts/add`) — full list of the user's `EmailAccount`s with checkbox per row. Disabled rows (status `:disconnected` / `:paused_bounces`) show why and aren't selectable. Save persists the selection (delta of `CampaignEmailAccount` rows); Cancel returns without changes.

Per-inbox daily quota is **not** edited here — it lives globally on `EmailAccount` and is set under `/email-accounts`. The capacity card just sums `daily_quota` across enrolled healthy inboxes.

### 4.3 Writing view (`/campaigns/:id/writing`) — one contact at a time

There is **no list of contacts**. The view is a single-contact workspace; on landing it picks the oldest `:pending_approval` and presents it. Rationale: the writer AI for contact N is supposed to learn from every edit on contact N-1, so the natural shape is sequential, not browsable.

Empty state (no pending contacts): a single card with the **"Bring in N enriched contacts"** button (see §3 promotion). After clicking, the view loads the first contact.

Layout (single column, max ~720px wide):

1. **Contact header card**: serif contact name + title, mono email; below it the company name + 1-line summary, employee count, industry. Right side: small mono `{inbox.address}` showing which inbox will send this.
2. **Sequence editor**: one card per step in the sequence, in order. Each card:
   - Top mono label: `Step N · Initial` / `· Followup 1` / `· Terminal: mark no_reply`.
   - Terminal step has no subject/body — just shows what'll happen after the last email.
   - For email steps:
     - **Subject input**, with a **"Preview in inbox"** button next to it → opens the demo Gmail panel (8 fake subjects, user's at row 4).
     - **Body textarea**, plain text, mono-ish font, ~14 line height, char counter.
   - Edits autosave to `user_subject` / `user_body` on blur. `ai_*` stays immutable.
3. **Bottom action bar** (sticky):
   - Primary: **"Approve & next"**. Disabled until every email step has non-empty subject and body.
   - Secondary: **"Skip"** (sets contact to `:no_reply` immediately, no emails sent — used when user decides this contact isn't worth pursuing).

On "Approve & next":
- `CampaignContact.status -> :approved`, snapshot the current `Sequence` (steps + delays + terminal) into `sequence_snapshot`, fill `assigned_email_account` (sticky, §5.1), schedule step 1's `Email` (§5.2). Followups stay as `:drafted` rows on the contact's `Thread` and get `scheduled_at` only when their parent sends.
- `auto_approve_streak += 1` iff every email step's `user_subject` and `user_body` are both nil (i.e. the user accepted every AI draft unchanged). Any edit at all resets nothing — the streak only counts clean approvals, but a non-clean one just doesn't increment. (The 10-threshold is cumulative, not consecutive.)
- View loads the next `:pending_approval` contact. The writer kicks off generation for it on landing (§6).

**Draft generation timing**: when the writing view loads a contact that doesn't yet have draft `Email`s, the view shows a skeleton state with a mono `drafting…` indicator and a pulsing dot, then streams the result in. Generation takes 3–8 s; the view stays responsive.

**Auto-approve mode** (when `auto_approve_on?` is true): new `:pending_approval` contacts never land in this view. A separate Oban worker (`AutoDraftAndApprove`, queue `ai_writer`) runs `EmailWriter` for each (leaving `user_*` nil), sets contact status `:approved`, schedules step 1. The writing view shows an empty state with a note: *"Auto-approve is on. New contacts go straight to scheduled."*

### 4.4 Sending funnel (`/campaigns/:id/sending-funnel`)

Top: 5-tile stats strip mirroring the enrichment funnel pattern (same component, different metric set):

| Tile | Source |
|---|---|
| Reply rate | `replied_* / sent` |
| Interest rate | `replied_interested / (replied_interested + replied_not_interested)` |
| Total sent | `count(emails.status == :sent)` |
| Daily avg | rolling-7-day mean |
| Bounce rate | `count(:bounced) / count(:sent)` — turns red ≥3%, banner ≥5% |

Below: **funnel bucket strip** — same prototype block style. One tile per bucket, click filters the table:
- Pending approval
- Step 1 sent (no followup yet)
- Step 2 sent
- Step N sent (one tile per defined step in sequence)
- Call ready
- Replied · interested
- Replied · not interested
- Replied · OOO
- No reply
- Bounced
- Failed

Below that: split-pane.
- **Left**: contact list filtered by selected bucket. Row: contact name, company, last-event mono timestamp.
- **Right**: thread view (§4.5) for the selected contact.

The Writing view is conceptually a special case of this — a tile click on "Pending approval" reuses the writing pane.

### 4.5 Thread view (right pane)

Vertical scroll, newest at bottom. Items in mixed timeline:
- Outbound email (sent / scheduled / failed) — paper card, mono `from→to`, subject, body.
- Inbound email — paperAlt background, sender chip.
- Note — italic serif, author + relative time.
- System events — mono one-liner ("Sequence halted · reply detected · classified as `interested`").

Header bar:
- Contact name (serif) + status badge with override dropdown.
- Buttons: `Stop sequence` (disabled if already terminal), `Mark as…` (manual category override).

Footer composer (sticky):
- Tab 1 **Reply** — rich-text editor (TipTap or `lexical-elixir`; pick whatever the project already pulls in or wire the lightest one). Sent via the same inbox that owns this thread. Saved as `Email{is_manual_reply: true, direction: :outbound, step_position: nil}` and threaded via `inReplyTo`.
- Tab 2 **Note** — plaintext, persists as `Note`.

### 4.6 Email accounts page (`/email-accounts`)

Global, lists all `EmailAccount` for the current user. We do **not** render our own OAuth UI — three buttons (Gmail, Outlook, IMAP) each `push_redirect` to Nylas's hosted auth URL. Nylas handles the entire connect flow and redirects back to `/email-accounts/callback?account_id=…&state=…`. The callback controller verifies state, fetches the account details from Nylas, and inserts/updates an `EmailAccount` row.

Per existing row: provider icon, address, status dot, "used in N campaigns" link, disconnect button (calls Nylas's revoke endpoint then soft-deletes the row).

### 4.7 Billing page

Placeholder. One card: "Plans coming soon", grayed primary button, plain copy "Liid is in invite-only beta. Reach out at hello@liid.app".

---

## 5. Sending engine

### 5.1 Inbox assignment (sticky)
On `CampaignContact` approval:
1. Pull all `CampaignEmailAccount` for the campaign where `paused? == false`.
2. Filter out any `EmailAccount.status != :healthy`.
3. Of the remaining, pick the one with the **lowest `(approved_contacts_today / daily_quota)` ratio**. Ties broken by inserted_at.
4. Bind `assigned_email_account_id` on the contact. Never reassigned (unless manually re-routed by user, deferred).

### 5.2 Scheduling
Computed at approval time for step 1, and at parent-send time for followups. One function: `next_slot(email_account, not_before_dt)` → returns a `DateTime`.

```
def next_slot(account, not_before):
  candidate = max(now, not_before) in account.tz
  candidate = bump_into_workday(candidate)        # Mon–Fri 09:00–17:00
  loop:
    today_count = emails scheduled or sent today for account
    if today_count >= effective_quota(account, today):
      candidate = tomorrow at 09:00; bump_into_workday; continue
    last = latest scheduled_at today for account
    if last == nil:
      return candidate                            # first slot of the day
    gap = candidate - last
    if gap < 60 min and today_count < burst_cap_today(account):
      return last + uniform(1, 5) minutes         # inside current burst
    else:
      candidate = last + 60 min                   # next burst
      candidate = bump_into_workday(candidate)
      continue
```

- `burst_cap_today(account)` is a per-(account, date) random pick in `6..12`, memoized.
- `effective_quota(account, date)` is `round(quota × uniform(0.85, 1.05))`, memoized.
- `bump_into_workday` snaps weekends + nights to next Mon–Fri 09:00.
- **Step 1 special rule**: when scheduling a step 1 email, replace the lower bound with `max(not_before, today_11am_in_account_tz)` before running the loop. Followups ignore the 11am floor.
- No mutex. Two concurrent scheduling calls can land within the same minute — fine, deliverability isn't that sensitive.

### 5.3 Send loop
- Oban cron job `SendDueEmails`, runs every 60s. Selects `Email{status: :scheduled, scheduled_at <= now}`, capped at 200 per tick.
- For each: check 24h dedupe → check campaign panic switch → check inbox paused → call `Colt.Nylas.send_message`. On success: store `nylas_message_id`, `nylas_thread_id`, set `status: :sent`, `sent_at`, and **schedule the next step** for this contact (compute `scheduled_at = sent_at + step.delay_days + next_burst_slot`).
- `Req` config inside the worker: `retry: false` per project convention. Oban owns retry. Max 3 attempts with exponential backoff; on final failure → `Email.status = :failed`, contact status updated only if all steps have run.

### 5.4 24h dedupe
At the top of every send job:
```elixir
case Colt.Resources.Email.recent_to(recipient, campaign_id, hours: 24) do
  {:ok, []} -> proceed
  {:ok, [_ | _]} -> raise "24h dedupe violation: #{recipient} in campaign #{campaign_id}"
end
```
The action `recent_to` lives on `Email`. Raising kills the job and surfaces in Oban dashboard + server logs.

### 5.5 Panic switch
`CampaignSendingSettings.panic_switch_on == true` → `SendDueEmails` skips every email in that campaign, no status change. Flipping it back resumes. Top-bar banner red when on. Located in sidebar's Sending section header (toggle), also reachable from sending-funnel header.

### 5.6 Auto-approve
- Counter `auto_approve_streak` increments on every approval where `user_subject` and `user_body` are both nil for every step (user accepted the AI version unchanged).
- At `>= 10`, `auto_approve_unlocked? := true`. Banner in writing view: *"You've accepted 10 AI drafts unchanged. You can enable auto-send in Sequence settings."*
- When `auto_approve_on?` is true, `PromoteToSending` for new contacts goes directly to `:approved` with `user_*` left nil and `auto_approved? = true`. They never appear in the writing queue.
- Any edit by user later in any contact resets `auto_approve_on?` to false (forces re-evaluation). Streak counter is not reset — unlock stays.

---

## 6. AI writer

Module: `Colt.Services.EmailWriter`. Service convention: `run(campaign_contact) → {:ok, %{steps: [...]}}` where each step is `%{position, subject, body}`.

Internal `with` steps:
1. `load_context/1` — campaign sequence (full step list including delays so the model knows e.g. "followup 1 ships 2 days after the first"), target contact's person (name, title, email) and company (summary, employees, industry, region, generic_email), language.
2. `collect_examples/1` — query `Email` rows in the campaign where `user_subject` or `user_body` is non-nil (i.e. the user edited the draft). **No ranking.** Cap at 20 to keep the prompt bounded. Each example returns `{before_ai, after_user, company_brief, person_brief}` so the model can match on industry, size, AND job title.
3. `build_prompt/1`:
   - System message: role ("cold-outreach writer in {language}, mimicking the user's tone"), sequence rules tied to the actual step shape ("step 1 opens cold; step 2 ships {delay} days later, references step 1 obliquely; final email adds gentle urgency without aggression"), constraints (plain text, tracker-friendly, no markdown, no signatures — the inbox appends those).
   - User message: target company brief + target person brief + sequence skeleton (positions, delays, terminal action) + examples block + a single integer `seed = :rand.uniform(100) - 1`. The instruction: *"If one of the examples closely matches the target's industry or person title, follow its style. If multiple match, use the seed to pick deterministically (seed mod N). If none match, write fresh."*
4. `call_model/1` — Claude 4.5 Sonnet via OpenRouter, JSON response, schema `{steps: [{position, subject, body}]}`.
5. `persist/2` — one `Email{status: :drafted, ai_subject, ai_body}` per step. `user_subject` / `user_body` stay nil; they are only set when the user edits in the writing view. Effective send content is `user_? || ai_?`.

**Trigger**: not on contact creation. Called from the writing LiveView when a contact is opened *and* its draft emails don't yet exist. Auto-approve mode bypasses the LiveView via the `AutoDraftAndApprove` Oban worker (queue `ai_writer`, concurrency 4) which calls the same `run/1`.

**Regeneration**: per-step "Rewrite" button in the writing view, same module with a `step_position` arg.

---

## 7. Inbound + reply categorization

### 7.1 Polling worker (no webhooks in v1)
- Oban cron `PollInbounds`, every 30s. For each `EmailAccount{status: :healthy}`:
  - Call `Colt.Nylas.list_messages(account, after: account.last_sync_at, folder: :inbox)`.
  - For each message: enqueue `IngestInboundMessage` with the message id.
  - On success: update `EmailAccount.last_sync_at = max(received_at)`.
- Idempotent — message ids are stored on `Email.nylas_message_id` with a unique identity, so re-ingesting the same message no-ops.
- Bounce notifications come through the same polling path: Nylas marks messages as bounce-related in the list response; we detect them in step §7.3 instead of treating them as replies.

### 7.2 IngestInboundMessage job
1. Fetch full message via `Colt.Nylas.get_message(message_id)`.
2. **Bounce detection first**: if the message is a bounce (Nylas flag or sender == MAILER-DAEMON / postmaster), route to §7.4 and skip thread attachment.
3. Match `nylas_thread_id` against existing `Email.nylas_thread_id`. If match → attach to that `Thread`.
4. Else, fallback: sender-domain match (§1.9). If a `CampaignContact` exists in the receiving inbox with `person.email` ending in `@{sender_domain}`, attach to its most recent thread, set `Email.auto_attached? = true`.
5. Else: store as orphan inbound (deferred handling — not part of v1 UI).
6. Insert `Email{direction: :inbound, status: :sent}`, set `Thread.last_activity_at`.
7. Enqueue `CategorizeReply` (skip if the message is our own send echoed back).

### 7.3 CategorizeReply
- Claude 4.5 Sonnet, JSON output `{category: "ooo|interested|not_interested|other", confidence: 0..1}`.
- Sets `Email.reply_category` and `CampaignContact.reply_category`.
- Halts the sequence: every `Email{status: :scheduled} ∪ {status: :drafted}` for this contact's thread → `:skipped`. Contact `status -> :replied`.
- Broadcasts on PubSub topic `campaign:{id}` → funnel and thread view refresh.

### 7.4 Bounce handling
- Bounced inbound → find the matching outbound `Email` by recipient + `nylas_thread_id` (or recent send to same address), set `status = :bounced`, `bounce_reason = …`.
- Recompute campaign bounce rate (§8). If trip: flip `panic_switch_on = true`.

---

## 8. Bounce monitoring & health

One rule, campaign-level only:
- After every bounce event (and on every 1000th send as a safety net), recompute `(bounce_count, sent_count)` for the campaign.
- If `sent_count ≥ 50` and `bounce_count / sent_count > 0.05`: set `Campaign.panic_switch_on = true`.
- Banner on every sending view, red: *"Campaign auto-paused: bounce rate {pct}%. Investigate before resuming."*
- Restoration is manual (user toggles the panic switch off after investigating).

No per-inbox pause logic in v1 — protecting the whole campaign is sufficient and removes the per-`CampaignEmailAccount` paused state machine.

---

## 9. Stats & funnel maths

All stats are computed actions on `Campaign` (`stats/1`), returning a struct read by the LiveView. **Cached via `Memoize`** with a 15-second TTL keyed on `{campaign_id}`. `Memoize.invalidate(Colt.Services.Stats, :for, [campaign_id])` on every send/reply/bounce event.

Bucket sizes for the funnel strip come from a single SQL query grouping `CampaignContact` by computed bucket. The computed bucket considers:
- `status` (terminal: replied_*, call_ready, no_reply, bounced, failed)
- For `status == :sending` or `:approved`: highest `step_position` in `emails` with `status == :sent` → maps to "Step N sent" bucket.

---

## 10. Phasing

Build top-to-bottom. Each phase has Acceptance bullets and ships independently. Clear context between phases.

**Marking phases done**: when a phase's Acceptance bullets all pass, the implementing agent **edits this doc** and changes the phase heading from `### Phase E3 — …` to `### Phase E3 — … ✅ done`. That way the next agent invoked with "implement next phase" can scan headings and immediately see what's outstanding. Don't mark partial completion; either all Acceptance bullets pass or the phase stays open.

### Phase E0 — Foundations ✅ done
- New left-sidebar layout (replace top stepper for campaign routes). Section labels per §4.
- `EmailAccount` resource + admin index page. No Nylas yet — manual seed in iex is enough.
- Empty `/email-accounts` and `/billing` placeholder routes.
- **Acceptance**: navigating any campaign route shows the sidebar with both Enrichment and Sending sections; sending links go to "coming soon" stubs.

### Phase E1 — Nylas client + hosted account connect ✅ done
- `Colt.Nylas` client (read Nylas docs live before writing; capture base URL, auth, key endpoints at top of module). Functions: `hosted_auth_url/2`, `exchange_callback/1`, `send_message/2`, `list_messages/2`, `get_message/1`, `revoke/1`.
- `/email-accounts` page: three buttons that `push_redirect` to `Colt.Nylas.hosted_auth_url(:google | :m365 | :imap, state: …)`. Callback controller at `/email-accounts/callback` persists `EmailAccount`.
- No webhook subscriptions in v1 — polling is added in E6.
- **Acceptance**: connect a real Google account through the hosted flow. iex helper `Colt.Nylas.send_message(account, to: "me@…", subject: "test", body: "hi")` delivers a real email and returns `{:ok, %{message_id: _, thread_id: _}}`.

### Phase E2 — Sequence + sending accounts views ✅ done
- `Sequence`, `SequenceStep`, `CampaignEmailAccount` resources. Add the sending-related attrs to `Campaign` (§3 inline block).
- Sequence editor LiveView (§4.1) — enforces exactly one terminal step at end. Sending accounts LiveView (§4.2).
- Visiting `/sequence` for the first time flips `Campaign.sending_initialized? = true` (used by the writing view to render the promotion button properly).
- **Acceptance**: design a 3-step sequence with a terminal step, pick 2 inboxes with quota 15 each, see the live capacity card update to ~30/day. Edit a delay — version stays the same. Add an email step — version increments.

### Phase E3 — Contact promotion + AI writer (no examples yet)
- `CampaignContact`, `Thread`, `Email` (drafted state only) resources.
- `Colt.Services.Sending.IngestEnriched` — one-shot service called from the writing view button. Inserts `CampaignContact{status: :pending_approval}` per `CampaignCompany` with a non-null `picked_person_id` that doesn't already have a contact row.
- `Colt.Services.EmailWriter.run/1` — drafts subject + body per email step using Claude 4.5 Sonnet. **No examples in this phase** (added in E9). Includes the sequence skeleton (positions + delays + terminal action) in the prompt so the model can reference followup timing naturally.
- **Acceptance**: take an existing campaign with enriched contacts; iex-call `IngestEnriched.run(campaign_id)` — see one `CampaignContact` per `picked_person`. iex-call `EmailWriter.run(contact)` — see one `:drafted` `Email` per email step on the contact's `Thread`, language matching the sequence setting.

### Phase E4 — Writing view (one-at-a-time approval) ✅ done
- LiveView §4.3. Single-contact workspace. Promotion button when empty. Per-step subject + body editors. Demo inbox panel.
- On open of a contact with no drafts: call `EmailWriter.run/1` synchronously (in a `Task` so the LiveView stays responsive — show skeleton + drafting state, then stream rows in via PubSub).
- On "Approve & next": snapshot sequence into `sequence_snapshot`, assign sticky inbox (§5.1), schedule step 1 (`Email.status = :scheduled`), increment `auto_approve_streak` only if every step's `user_subject` and `user_body` are both nil, load next pending contact.
- "Skip" button → contact straight to `:no_reply`.
- **Acceptance**: bring in enriched contacts; approve one with edits (streak stays 0), approve one without edits (streak goes to 1); verify `assigned_email_account_id` set, snapshot present, step 1 has a `scheduled_at` in the next burst window; subsequent contact's draft includes nothing learned yet (E9 will fix that).

### Phase E5 — Send loop + scheduler ✅ done
- `SendDueEmails` Oban cron every 60s.
- Burst scheduler per §5.2.
- 24h dedupe with raise.
- On send: schedule next step, fire PubSub.
- Panic switch wiring (toggle in sidebar header).
- **Acceptance**: approve a contact, watch step 1 send within the burst window (or be visibly scheduled for next workday morning if outside hours). Toggle panic; subsequent ticks skip. Manually insert a duplicate `Email` to the same recipient and watch the job raise.

### Phase E6 — Inbound polling + reply categorizer ✅ done
- `PollInbounds` Oban cron, 30s, per healthy `EmailAccount`. Uses `last_sync_at` cursor.
- `IngestInboundMessage` Oban job (thread match by `nylas_thread_id` + domain fallback).
- `CategorizeReply` job (Claude 4.5 Sonnet, 4-way category).
- Sequence halt on any reply: all `:drafted` and `:scheduled` emails on the contact's thread flip to `:skipped`.
- **Acceptance**: send a test email, reply from a personal address, see the reply attach to the thread within ~60s with a category set. Cross-domain check: reply from a colleague's address in the same domain attaches to the same thread.

### Phase E7 — Thread view (read + manual interactions) ✅ done
- §4.5 thread timeline (read).
- Rich-text reply composer (tab 1) sending via Nylas.
- Notes (tab 2).
- Stop sequence button + manual status override.
- **Acceptance**: send a manual reply from the thread view, see it arrive at the recipient with the same `In-Reply-To`. Add a note. Stop sequence — all scheduled emails for the contact flip to `:skipped`.

### Phase E8 — Sending funnel ✅ done
- §4.4. Stats strip + bucket strip + split-pane (list left, thread right).
- Tile click filters list, row click selects contact.
- Writing view becomes the pending-approval bucket's right pane.
- **Acceptance**: every metric in the strip matches a hand-computed SQL query. Funnel sums to total contacts.

### Phase E9 — Writer learning loop (examples + A/B seed) ✅ done
- `collect_examples/1` (§6 step 2). No ranking, cap 20, include person details. Add the random seed integer + the "pick by seed mod N" instruction to the prompt.
- **Acceptance**: edit a draft to add a project-specific phrase. Next contact's draft incorporates that phrase or tone. With two distinct example styles in the campaign, observe over ~10 generated contacts that both styles appear roughly proportionally (a fully deterministic check is hard — eyeball is fine, but log the chosen seed per generation for auditability). Document in the writer module how to inspect the full prompt for one contact via iex.

### Phase E10 — Auto-approve unlock ✅ done
- Counter wiring, unlock at 10. Toggle appears in sequence view once unlocked.
- Auto-approve path: new `AutoDraftAndApprove` Oban worker (`ai_writer` queue). Runs when `auto_approve_on?` is true and `IngestEnriched` (or the writing-view promotion) inserts new `:pending_approval` rows. Leaves `user_*` nil, sets contact status `:approved`, schedules step 1.
- **Acceptance**: simulate 10 untouched approvals (iex), toggle appears in sequence view; flip on; bring in new contacts — they never enter pending_approval and step-1 emails appear scheduled.

### Phase E11 — Bounce monitoring + auto-pause ✅ done
- §8. Campaign-level bounce-rate computation, panic-switch auto-flip at 50 sends / 5% threshold. Red banner.
- **Acceptance**: simulate a bounce burst on a test campaign with seeded sends; campaign auto-pauses at 50/5%. Send loop honors the panic switch immediately.

### Phase E12 — Open/click tracking
- Per-campaign toggle, tracking-domain field + CNAME setup card.
- Nylas send call passes tracking flags per-message.
- Stats strip gains optional open + click rate tiles when enabled.
- **Acceptance**: enable on a test campaign, send to a known address with image-loading, observe open event arriving via Nylas webhook within minutes.

### Phase E13 — Billing placeholder + polish
- Static `/billing`.
- Visual pass over every sending view against the design system.
- Empty states.

---

## 11. Deferred (intentionally out of v1)

- Webhooks (we poll Nylas for inbounds in v1 — add webhooks later if latency matters).
- Per-inbox auto-pause on bounce rate (campaign-level pause is the only stop in v1).
- Holiday calendars in scheduler.
- Team multi-user campaigns (still single-user-owned per project rules).
- Reassignment of in-flight contacts to a different inbox.
- Auto-promotion of enriched contacts (v1 uses a button).
- Cross-campaign threads.
- Orphan inbound UI (matches no thread, no domain).
- Plain Notes attached to anything other than a Thread.
- Importing contacts not produced by enrichment.
- Warmup. We rely on the user starting from already-warm Gmail/M365 accounts.

---

## 12. Open questions

These are for explicit user follow-up before their respective phase:

**Resolved settings** (locked in):
- First emails (step 1) always schedule for the next available burst slot at or after **11:00** in inbox TZ. Followups use normal burst rules.
- Send-loop tick: **30s**.
- Inbound polling: **30s**.
- Reply categorizer confidence: model output below **0.7** is forced to `:other` regardless of label.
- `Email.writer_meta` jsonb stores `{seed, picked_example_email_id, prompt_token_count}` per generated email — for later analysis of which user-styles convert. Not surfaced in UI in v1.
- Tracking domain: **site-wide single domain**, set under `/admin/tracking-domain` (admin-only). Per-campaign toggles still flip whether tracking is *applied*, but they all use this one CNAME. Revisit only when user count or domain-isolation pressure warrants it.

**Open at launch (not blocking dev)**:
- Sign Nylas DPA before connecting any real client mailbox. EU region (`api.eu.nylas.com`) handles data residency; DPA covers the processor relationship.
