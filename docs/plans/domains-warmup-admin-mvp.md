# Admin-only domain buying + inbox provisioning + warmup pipeline

## Context

`docs/specs/domains-warmup.md` already scoped a full customer-facing version of this feature (buy a sending domain, provision inboxes via Mailpool, warm them via Mailivery, gated behind Stripe billing) but it was never built — status was "researched & scoped, not building yet," blocked mainly on confirming Mailpool actually exposes raw IMAP/SMTP credentials.

Krister wants to prove the pipeline works for himself first, with no customers and no billing: he pays vendors directly out of pocket, the whole thing lives behind an admin-only tab on the existing Email Accounts page. This plan is the stripped-down version of the old spec: same three vendors (Realtime Register / Mailpool / Mailivery), no Stripe, no DomainOrder, admin-gated UI, built in three risk-ordered phases so the two confirmed-solid vendors (Realtime Register, Mailivery) don't get blocked on the one real unknown (Mailpool's credential exposure).

Locked decisions from this conversation:
- **No sending gate.** Provisioned inboxes appear in the normal Inboxes tab immediately, no `sending_starts_at`, no scheduler changes. Warmup status is informational only for now.
- **`daily_quota` stays at 15.** Not touched by this work.
- Mailpool does **not** support `.ee`/`.fi` (confirmed by hand-testing) — irrelevant here since Mailpool is only used for mailbox creation, not domain purchase; Realtime Register remains the registrar.
- `Colt.Nylas.create_imap_grant/1` already exists — the BYO-IMAP half of the pipeline is not new code, just a consumer of an existing function.

## Step 0 — Update `docs/specs/domains-warmup.md` first

Before any code, edit the doc to reflect the reduced scope so it stays the source of truth:
- Rewrite §1 UX as admin-only: Email Accounts page gains **Inboxes / Domains / Warmup** tabs, Domains+Warmup visible only to `is_admin`. Drop the target-volume calculator — selection is manual (checkboxes + manual add + one shared inbox-count number), not computed.
- §2 stack table: delete the Stripe/payment row; add a one-line note that billing is deferred, Krister funds vendor accounts directly.
- §4 decisions: strike the Stripe/DomainOrder and Täp-OÜ-registrant decisions; note `SendingDomain.belongs_to :user` is kept for forward-compatibility even though there's one user today.
- §6 data model: remove `DomainOrder`; add the new `SendingDomain` and `EmailAccount` fields (below).
- §7 services: remove `CreateCheckout`/`FulfillOrder`; add `Domains.PurchaseDomains` (direct, no webhook) plus the new warmup-toggle/stats services.
- §9 billing plumbing: delete for this version, one-line pointer to "customer-facing follow-up."
- §10 UI: rewrite for the three-tab structure and two wizards.
- §11 phase plan: replace with the phase breakdown below.
- Add a status line: `**Status: SCOPE REDUCED (admin-only, no billing) — 2026-08-28.**`

## Data model

**New resource `Colt.Resources.SendingDomain`** (`lib/colt/resources/sending_domain.ex`, registered in `lib/colt/domain.ex`), modeled on `EmailAccount`'s shape:
- `name` (identity), `source_domain`, `tld`, `registrar` (`:realtime_register`), `registrar_order_id`, `status` enum: `:pending_purchase -> :purchasing -> :registered -> :provisioning -> :active | :purchase_failed | :provisioning_failed | :expired`, `registered_at`, `expires_at`.
- `belongs_to :user` (mirrors `EmailAccount`, forward-compatible with customer-facing later), `has_many :email_accounts`.
- Policies: `bypass actor_attribute_equals(:is_admin, true) do authorize_if always() end`, same pattern as 16 other resources already using it.
- Actions: `create :create_pending`; per-transition updates `mark_purchasing/registered/purchase_failed/provisioning/active/provisioning_failed`; reads `list_for_user`, `list_active_for_user`, `list_all`.
- **No `DomainOrder` resource** — no billing trail needed at this scope.

**Extend `Colt.Resources.EmailAccount`** (`lib/colt/resources/email_account.ex`):
- `belongs_to :sending_domain, allow_nil?: true`
- `provisioning_source` (`:oauth | :mailpool`, default `:oauth`)
- `mailpool_mailbox_id`, `warmup_external_id` (Mailivery id)
- `warmup_enabled` (boolean, default `true`) — the per-inbox toggle
- `warmup_status` (`:pending | :warming | :healthy | :paused | :failed`, default `:pending`)
- New action `update :toggle_warmup` (arg `enabled`)
- New reads `list_provisioned_for_user` (filter `provisioning_source == :mailpool`), `list_by_sending_domain`

Single migration: `mix ash_postgres.generate_migrations add_sending_domains_and_warmup_fields`.

## External service clients

All three follow `Colt.Nylas`'s house style: private `request/3` (`Req.request`, `retry: false`, `receive_timeout: 30_000`), private `config!/0` via `Application.fetch_env!(:colt, :x)` + `Keyword.fetch!`, `handle/2` normalizing to `{:ok, _} | {:error, _}`.

- **`Colt.Registrar`** (behaviour, thin dispatch on `Application.get_env(:colt, :registrar_impl, ...)`) + **`Colt.Registrar.RealtimeRegister`** (`lib/colt/registrar.ex`, `lib/colt/registrar/realtime_register.ex`): `check/1`, `register/2`, `renew/2`. No `set_dns/2` yet — deferred until Phase 2 confirms whether Mailpool needs DNS records set and by whom.
- **`Colt.Provisioning`** (behaviour) + **`Colt.Provisioning.Mailpool`** (`lib/colt/provisioning.ex`, `lib/colt/provisioning/mailpool.ex`): `create_mailbox/3` (returns `imap`/`smtp` maps shaped to match `Colt.Nylas.create_imap_grant/1`'s expected settings exactly — this is the pipeline's critical seam), `fetch_credentials/1`, `delete_mailbox/1`. Swappable to Mailreef with zero other code changes if Mailpool fails the creds check.
- **`Colt.Mailivery`** (`lib/colt/mailivery.ex`, no behaviour — single vendor, well-documented, YAGNI on swap indirection): `enroll/1`, `start/1`, `pause/1`, `resume/1`, `health/1`, `metrics/2`, `placement/1`.

New `runtime.exs` blocks: `:realtime_register`, `:mailpool` (or under `:provisioning`), `:mailivery` — same pattern as existing `:nylas`/`:openrouter`.

## Services (`lib/colt/services/domains/`)

1. `Domains.SuggestNames.run(source_domain)` — OpenRouter, same-TLD candidates.
2. `Domains.CheckAvailability.run([names])` — `Colt.Registrar.check/1` per name, parallel.
3. `Domains.PurchaseDomains.run(user, [names])` — per name: `create_pending` → `Registrar.register/2` → `mark_registered`/`mark_purchase_failed`. Partial success is fine. **Runs synchronously in the LiveView event**, not Oban (fast, small batch, single REST call each).
4. `Domains.GenerateInboxDrafts.run(domains, count_per_domain)` — AI-generates `count_per_domain * len(domains)` person names + local-parts, country-appropriate per TLD. Pure, no DB writes.
5. `Domains.ProvisionInboxes.run(sending_domain_id, draft)` — per-inbox chain: `Provisioning.create_mailbox/3` → `Nylas.create_imap_grant/1` → `EmailAccount.create_provisioned` → `Mailivery.enroll/1` + `start/1` → `mark_active`/`warmup_status: :warming`. One service, four sequential steps (precedent: existing `ConnectImapMailbox`), called once per inbox.
6. `Domains.ToggleWarmup.run(email_account, enabled)` — `Mailivery.pause/1|resume/1` then `toggle_warmup` action. Synchronous, single call.
7. `Domains.WarmupStats.run(email_accounts)` — per-inbox 7-day warmup-vs-real counts + global 24h warmup total. **Computed live on page load**, not stored/cron-polled — low-traffic admin page, staleness would undermine the "is it actually running right now" purpose. Real-sent counts come from the existing `OutboundEmail.list_sent_for_user_since!`-style query, not from Mailivery (Mailivery only knows about warmup traffic it sent).

## Oban

New queue `provisioning: 3` in `config/config.exs`. `Colt.Jobs.ProvisionInbox` (`lib/colt/jobs/provision_inbox.ex`): `max_attempts: 5`, `unique: [keys: [:sending_domain_id, :local_part], period: 3600, states: [:available, :scheduled, :executing, :retryable]]`, one job per drafted inbox — mirrors `Jobs.ImportMailbox`. Note for implementation: make `ProvisionInboxes.run/2` resumable (e.g. persist a `:pending` `EmailAccount` row as soon as the Mailpool mailbox exists, before Nylas/Mailivery run) so a retry doesn't recreate a Mailpool mailbox that already succeeded.

`PurchaseDomains` stays synchronous — no job needed for a handful of fast registrar calls.

No new cron job — warmup stats are live-computed, not polled.

## UI

Tab mechanism: **`?tab=` query param** handled in `handle_params` on the existing `EmailAccountsLive` route (`/email-accounts`) — bookmarkable/refresh-safe, and lets admin-gating happen as a `handle_params` redirect (`push_navigate` non-admins away from `domains`/`warmup` back to `inboxes`) rather than template branching. No existing tab pattern in the app, so this sets the precedent. Route/`on_mount` stays `:live_user_required` (Inboxes must stay open to everyone); admin gating happens per-tab inside the LiveView, backstopped by the Ash policy bypass at the data layer.

File split (mirrors existing `email_accounts_live.ex` + `email_account_detail_live.ex` separation):
- `email_accounts_live.ex` — tab shell, wraps existing Inboxes markup as the default tab.
- `domains_tab_live_component.ex` — source-domain input → AI suggestions + manual-add checkboxes → buy → purchased-domains list with "Set up inboxes" per domain.
- `inbox_setup_live_component.ex` — domain checkboxes + single count input → generated batch review (read-only review + regenerate, no inline editing) → confirm enqueues `Jobs.ProvisionInbox` per row.
- `warmup_tab_live_component.ex` — per-inbox list: address, warmup on/off toggle, 7-day warmup-vs-real counts, plus a top-of-tab 24h global total banner.

Nav-level: only render Domains/Warmup tab links when `@current_user.is_admin`.

## Phase breakdown

**Phase 1 — Registrar + domain suggest/purchase.** No live vendor account needed beyond a free Realtime Register OT&E sandbox. Build: `SendingDomain` + migration, `Colt.Registrar`/`RealtimeRegister`, `SuggestNames`/`CheckAvailability`/`PurchaseDomains`, Domains tab UI, tab shell + `?tab=` + admin gating. Ship "Set up inboxes" as a disabled placeholder.

**Phase 2 — Mailpool provisioning. Gated on manual verification first**, not code: confirm with Mailpool that raw IMAP/SMTP creds are exposed per mailbox. Meanwhile, buildable without that answer: `EmailAccount` schema changes + migration, `Colt.Provisioning` behaviour, `GenerateInboxDrafts`, the inbox-setup review UI tested against a stub `Provisioning` impl (verifies the real Nylas-grant half end-to-end). Once confirmed: real `Colt.Provisioning.Mailpool`, `provisioning` Oban queue + `Jobs.ProvisionInbox` wired live. If Mailpool fails the check, swap to Mailreef behind the same behaviour with no other changes.

**Phase 3 — Mailivery warmup.** Lowest remaining risk, just needs an account/API key. `Colt.Mailivery` client, extend the provisioning chain with enroll+start, `ToggleWarmup`/`WarmupStats`, Warmup tab UI.

## Open items to resolve during build (not blocking the plan)

- Whether Mailpool needs DNS (SPF/DKIM/DMARC) set on the domain before provisioning, and who sets it (Realtime Register DNS API vs. Mailpool auto-config) — investigate during Phase 2's manual Mailpool check.
- Realtime Register production base URL and which registrant/admin-contact identity to use for `.ee` domains bought under Krister personally (sandbox testing unaffected).
- Mailivery's exact "resume" endpoint (docs only confirm pause/start) — confirm during Phase 3.

## Verification

- Phase 1: run through the Domains tab against the Realtime Register OT&E sandbox — enter a real test domain, confirm AI suggestions come back same-TLD, confirm availability checks and manual-add work, confirm a sandbox "purchase" creates a `SendingDomain` row with correct status transitions.
- Phase 2: with the stub provisioning impl, confirm a full inbox-setup run creates real Nylas grants and `EmailAccount` rows end-to-end; once Mailpool is confirmed, redo with the real impl and verify a purchased mailbox shows up correctly in the Inboxes tab.
- Phase 3: enroll a real provisioned inbox in Mailivery, confirm warmup traffic starts, confirm the Warmup tab's 7-day and 24h numbers move as expected, confirm the toggle actually pauses/resumes via Mailivery's dashboard.
