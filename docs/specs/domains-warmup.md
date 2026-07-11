# Warmup domains & inboxes — client-provisioned sending infrastructure

**Status: RESEARCHED & SCOPED, NOT BUILDING YET (2026-07-11).** Every external
service was verified against its real API/pricing, the stack is chosen, and all
the product decisions are locked (see §4). This doc is the spec to build from
when we pick it up. Nothing here is implemented.

Scope: let a client buy **fresh sending domains + inboxes** through Liid, have
them **warmed up automatically**, and then send campaigns from them once warm.
Today a user connects their *own* already-warm Gmail/M365 inbox via Nylas
(`EmailAccount`); this feature *provisions new burner domains* for clients who
don't have spare warm inboxes. Warmup was explicitly out of scope until now
(`docs/email-sending.md` §warmup: "we rely on the user starting from already-warm
accounts") — this feature is what changes that.

---

## 1. The product (UX)

On the **user-level email-accounts screen** (`/email-accounts`, not the
per-campaign one) the user hits **"Buy domains"**:

1. Enter the client's **real company domain** (the source, e.g. `example.ee`).
2. A **calculator**: user enters **target emails/day**; we show how many domains
   that is. Math: **3 inboxes per domain × 20 emails/day/inbox = 60/day/domain**,
   so `domains = ceil(target_daily ÷ 60)`.
3. We **AI-generate** candidate domain names (see §5) in the **same TLD** as the
   source, morphologically clever and language-specific — plurals, englishified
   slang, near-forms (`liid.ee` → `liidid.ee`, `liids.ee`, `liide.ee`), *not*
   dumb `get-/try-` prefixes.
4. We **check availability** on each candidate and surface **only available**
   ones as checkboxes. User picks (or all).
5. **Buy** → Stripe one-off payment (they're already subscribed).
6. On payment: register domains, provision 3 inboxes each, set DNS, **start
   warmup automatically**. DB records `warmup_started_at` + `warmup_until`
   (~21 days).
7. User continues writing emails. Campaigns from these inboxes are **scheduled
   to start after warmup**, not now — the scheduler holds them until the inbox
   is warm.

## 2. The stack (chosen)

| Layer | Pick | Swap-in alt | Notes |
|---|---|---|---|
| **Registrar** | **Realtime Register** (NL) | Netim (REST) / Ascio (SOAP, Nordic) | Direct `.ee` accreditee, REST register API, sandbox |
| **Inbox host** | **Mailpool** | **Mailreef** | Provisions inboxes + DNS; **API docs are request-only** |
| **Warmup** | **Mailivery** (Berlin) | MailReach (per-inbox) | Documented API, placement tests, **flat** pricing |
| **Send path** | **Nylas BYO-IMAP grant** | — | Reuses the whole existing send pipeline |
| **AI naming** | **OpenRouter** (already wired) | — | Domain candidates + sender names, per-market |
| **Payment** | **Stripe** (already wired) | — | One-off `mode: payment`, fork of existing checkout |

### 2.1 Why this registrar (the key insight)
**The `.ee` registry fee is a flat €6 + VAT/year with no volume discount** —
internet.ee charges *every* registrar exactly €6. So every reseller's floor is
€6 + their margin, and nobody can meaningfully undercut. That explains the whole
landscape:
- Zone.ee retail €8.37 excl VAT is only €2.37 over cost — near-floor, but its
  API is **management/DNS only, cannot register** (confirmed from its 93-path
  OpenAPI spec: only list/renew/cancel, no create, no availability, no sandbox).
- International resellers **gouge** `.ee` because they don't specialize in it:
  Netim €12, INWX €39, Gandi €48, Openprovider list $84, EuroDNS €56.
- **No Estonian-native registrar exposes a register API** (all WHMCS/HostBill
  storefronts over a private EPP link). IV.lt carries `.ee` at €22. group.one is
  acquiring Estonia's Veebimajutus/Elkdata (announced Nov 2025) — a future watch,
  not available today.
- Becoming an accredited registrar ourselves (€6 wholesale, `€600 + €1,200`
  float, knowledge+EPP test) was **rejected** — we integrate vendors, we don't
  operate registrar infrastructure.

**Realtime Register** wins because it's a **direct `.ee` accreditee** (no
reseller-of-reseller stacking) *and* has a modern turnkey API:
- Register: `POST /v2/domains/{name}` (JSON). Availability:
  `GET /v2/domains/{name}/check` — returns *your account's* live price.
- **OT&E sandbox** `https://api.yoursrs-ote.com/`, UI `dm.yoursrs-ote.com`.
- Auth: `Authorization: ApiKey <key>`. Official PHP + TypeScript SDKs.
- Prepaid reseller balance (front the cost, bill via Stripe). Carries
  `.com`/`.io` + 2000 TLDs too.
- Docs: `https://dm.realtimeregister.com/docs/api/`
- **Caveat:** like *every* wholesaler, its `.ee` price is **login-gated** — the
  only way to see the real number is to open the free sandbox and call `check`.
  As a direct accreditee it should sit near the €6 floor, well under Netim's €12.

### 2.2 Why Mailpool (with an adapter) + the risk
Mailpool provisions inboxes (own-SMTP $3, Google Workspace $4, M365 $5 per
inbox/mo) with automated SPF/DKIM/DMARC and bulk domain/DNS. **But: it has NO
built-in warmup and NO real placement-test API** (multiple independent reviews
confirm; they tell users to warm via Smartlead/Instantly — which we avoid). And
**its API documentation is request-only** — no public base URL, auth, endpoints,
or sandbox. So:
- **The make-or-break unknown:** we need the **raw IMAP/SMTP username+password
  per mailbox** to (a) create the Nylas grant and (b) enroll in warmup. If
  mailpool only exposes "connect to sequencer X" integrations and won't hand
  over raw creds, the plan breaks. **Verify with mailpool before building §Phase 4.**
- Mitigation: provisioning sits behind a `Colt.Provisioning` behaviour so we can
  swap to **Mailreef** (comparable provisioner, same creds question applies) with
  no rework.

### 2.3 Why Mailivery for warmup
- EU company (Berlin, 2020). **Fully documented API** (`https://mailivery.readme.io`,
  base `https://app.mailivery.io/api/v1`, `Authorization: Bearer`): enroll via
  `POST /createcampaignwithsmtp` (also gmail/microsoft/oauth), control via
  `/startwarmup` `/pausewarmup` `/enablerampup` `/updateemailperday`, monitor via
  `/gethealthscore` `/getmetrics`, and **placement results via `GET /gettestresults`**.
  Webhooks for connect/warmup events.
- **Placement tests on every plan** (the requirement mailpool fails).
- **Flat pricing** — $29 (200/day) / $79 (800/day) / $199 (2,500/day),
  **unlimited mailboxes**, shared daily warmup-volume cap. This makes warmup a
  near-fixed app-level cost, not per-inbox — which is why we can fold it into the
  monthly package (§4).
- **Two things to confirm with their DPA/sales:** (a) whether the warming **pool
  can be EU-constrained** — *no* warmup vendor documents pool geography publicly,
  and Warmbox/lemwarm are explicitly *global*; Mailivery is at least an EU
  company; (b) that the $199 shared 2,500/day cap is enough headroom (~50-60
  inboxes warming concurrently) as clients onboard.
- Alternative: **MailReach** (Paris, documented API, placement tests) but
  **$19.50/inbox** — kills the flat-cost economics; IMAP support unconfirmed.
  Warmforge (Tallinn, cheapest $10-12/inbox) has an **undocumented** API and only
  natively warms Google/M365. Warmbox rejected (global pool, no real API docs,
  reviews report aggressive volumes suspending young domains).

### 2.4 Why Nylas BYO-IMAP (send path)
Every inbox today is a **Nylas grant** and all sending is `Colt.Nylas.send_message`.
New inboxes must enter that pipeline (the user chose this over a parallel SMTP
path). Nylas supports it cleanly:
- **Bring-Your-Own-Auth**, fully server-side, no OAuth redirect:
  `POST https://api.eu.nylas.com/v3/connect/custom` with `provider: "imap"` +
  `settings: {imap_username, imap_password, imap_host, imap_port, smtp_host, smtp_port}`.
  Returns `grant_id`. Requires the IMAP connector created once:
  `POST /v3/connectors {"provider":"imap"}`.
- **Always include the SMTP block** (omitting it makes sends fail later).
  Idempotent per email address; 3 wrong-password attempts → `auth_limit_reached`.
- **Pricing:** Full Platform $15/mo incl. 5 grants, then **$2/grant/mo**. Billed
  on **peak** grant count during the month, **no proration** — so **provision in
  monthly batches and prune dead grants before month-end**, or churn bills full.
- IMAP grants are **fragile**: they expire when the mailbox password changes/is
  revoked — need re-provision/monitoring (watch grant-expired webhooks). Email
  only (no calendar — irrelevant here).
- **Confirm** BYO custom-auth is enabled on the current Nylas plan (docs don't
  state a gate; may need a word with sales).
- Docs: `https://developer.nylas.com/docs/v3/auth/bring-your-own-authentication/`

## 3. Cost math — per domain (3 inboxes ≈ 60 emails/day)

| Component | Unit | Per domain | Cadence |
|---|---|---|---|
| Domain (Realtime Register `.ee`) | ~€6-8/yr (TBC via sandbox) | ~€7/yr | **yearly** |
| Mailpool inbox (own SMTP) | $3/inbox/mo | $9/mo | monthly |
| Nylas grant | $2/inbox/mo | $6/mo | monthly (peak, non-prorated) |
| Warmup (Mailivery, flat) | ~$199/mo shared | ~$3/mo amortized | monthly (app-level) |
| **Total** | | **≈ €17/mo + ~€7/yr** | ≈ **€6/inbox/mo** |

Google Workspace / M365 mailpool inboxes add ~$1-2/inbox if ever wanted. The
~€17/domain/mo is the number to price packages around.

## 4. Decisions locked

1. **Billing:** the domain is a **one-off Stripe charge** (`mode: "payment"`),
   re-charged on expiry (~yearly). The recurring infra (mailpool + Nylas +
   warmup, ~€17/domain/mo) is **absorbed into the existing subscription packages**
   — packages just include N sending-domains of capacity. No second recurring
   line. (Rationale: warmup is flat/near-fixed and Nylas is already inside the
   monthly; buying a domain once then paying monthly-extra felt wrong to the user.
   Burner domains may go stale in a year anyway → pay-once, pay-again-on-expiry.)
2. **Warmup gate:** an inbox becomes send-eligible at the **later of 21 days AND
   a healthy Mailivery score** — never send from a still-cold inbox.
3. **Domain owner:** all domains registered under **Täp OÜ** (our entity); the
   client *rents*. Cleanest for `.ee` registrant identity + auto-renew on our
   balance. Client loses the burner domains on churn (fine).
4. **Provisioning:** build behind a swappable adapter; **verify mailpool exposes
   raw IMAP/SMTP creds before committing** — else swap to Mailreef.
5. **Registrar:** Realtime Register, behind a `Colt.Registrar` adapter (swappable).
6. **Send volume:** **20 emails/inbox everywhere** — change the global
   `EmailAccount.daily_quota` default from **15 → 20**.
7. **AI everything nameable:** domain candidates *and* sender local-parts are
   **OpenRouter-generated per market/language** (§5). No manual name input.
8. **No anti-sniping machinery:** just buy. The only hard rule is that *suggested*
   domains are genuinely available (availability check stays in the suggest step).
   Rare post-payment registration failure → refund that domain's slice + notify.

## 5. AI generation (OpenRouter — already `config :colt, :openrouter`)

- **Domain candidates:** prompt the model with the source domain/brand + the
  campaign market/language → morphological variants (plural, diminutive,
  englishified slang, near-forms), same TLD. Then availability-check each; surface
  only available. (Example the user gave: `liid.ee` → `liidid.ee` [plural],
  `liids.ee` [englishified slang], `liide.ee`.)
- **Sender names:** generate country-appropriate first names per market for the
  3 `firstname@domain` local-parts. Real-person-style beats role addresses
  (`info@`/`hello@`) for deliverability.

## 6. Data model (Ash resources)

Owner is **`Colt.Accounts.User`** (no orgs). New/changed:

- **`SendingDomain`** (`belongs_to :user`) — `name`, `source_domain`, `tld`,
  `registrar` (`:realtime_register`), `registrar_order_id`, `status`
  (`pending_payment → registering → provisioning → warming → active | failed |
  expired`), `registered_at`, `expires_at`, `warmup_started_at`, `warmup_until`;
  `has_many :email_accounts`. Identity on `[:name]`.
- **`DomainOrder`** (`belongs_to :user`) — one Stripe one-off payment covering N
  domains; `stripe_session_id`, `amount`, `status`; `has_many :sending_domains`.
  The unit for partial refunds.
- Extend **`EmailAccount`** (`lib/colt/resources/email_account.ex`):
  `belongs_to :sending_domain` (nullable — existing OAuth inboxes have none),
  `provisioning_source` (`:oauth | :mailpool`), `mailpool_mailbox_id`,
  `warmup_external_id`, `warmup_status` (`:pending | :warming | :healthy |
  :failed`), and **`sending_starts_at`** (the scheduler floor). Provisioned
  inboxes get `daily_quota: 20`.

Register new resources in `lib/colt/domain.ex`. Migrations via
`mix ash_postgres.generate_migrations`.

## 7. External wrappers & services (house style: `Req`, `run/…` + `with`, `{:ok,_}`)

Model on `Colt.Nylas` (private `request/3`, `config!/0` reading `runtime.exs`,
`retry: false` — Oban owns retries).

**Wrappers**
- `Colt.Registrar` behaviour + `Colt.Registrar.RealtimeRegister` — `check/1`,
  `register/2`, `set_dns/2`, `renew/2`.
- `Colt.Provisioning` behaviour + `Colt.Provisioning.Mailpool` — `create_mailbox`,
  `fetch_credentials`, `delete_mailbox`.
- `Colt.Mailivery` — `enroll/1`, `start/1`, `pause/1`, `health/1`, `placement/1`.
- `Colt.Nylas` — **add** `connect_custom/1` (BYO IMAP grant) + connector setup.

**Services**
- `Domains.SuggestDomains.run/1` — source + volume → OpenRouter candidates →
  `Registrar.check` each → available list + domain count.
- `Domains.CreateCheckout.run/2` — fork of `Billing.CheckoutCreate` with
  `mode: "payment"` + per-domain `price_data` → `DomainOrder`.
- `Domains.FulfillOrder.run/1` — from webhook `checkout.session.completed`
  (mode=payment) → `Registrar.register` each → enqueue provisioning.
- `Domains.ProvisionDomain.run/1` (Oban) — DNS (MX/SPF/DKIM/DMARC) → 3× mailpool
  mailbox → fetch creds → 3× `Nylas.connect_custom` (create `EmailAccount`s,
  `sending_starts_at = now + 21d`) → 3× Mailivery enroll+start → domain `:warming`.
- `Domains.CheckWarmup.run/0` (cron) — poll Mailivery health; unlock inbox at
  later-of(21d, healthy); domain `:active` when all three ready.

## 8. Scheduler hooks (reuses the existing pipeline — the tidy part)

- `Colt.Services.Sending.NextSlot.run/3` (`lib/colt/services/sending/next_slot.ex`)
  — add `sending_starts_at` as a floor on `base` alongside the existing step-1
  floor: `base = max(now, not_before, sending_starts_at)`. Scheduling is stateless
  per-day, so no migration of existing scheduled rows.
- `Colt.Services.Sending.AssignInbox.run/2`
  (`lib/colt/services/sending/assign_inbox.ex`) — exclude inboxes whose
  `warmup_status != :healthy` or `sending_starts_at` is in the future.
- `daily_quota` default 15 → **20** (affects existing inboxes too, per decision 6).

Everything downstream — `SendDueEmails` dispatcher, `SendOne`, burst windows,
health/pause — is untouched.

## 9. Billing plumbing (fork of what exists)

- **Checkout:** `Colt.Services.Billing.CheckoutCreate` is subscription-mode;
  fork to a `mode: "payment"` one-off reusing `ensure_customer` +
  `client_reference_id`. Lib is `stripity_stripe ~> 3.0`.
- **Webhook:** `ColtWeb.StripeWebhookController` → `Billing.SubscriptionSync`
  pattern-matches `%Stripe.Event{}`. Add a `checkout.session.completed` branch
  keyed on `mode: "payment"` + a `domain_order` metadata tag → `FulfillOrder`.
  (Raw-body plug `StripeBodyReader` + `POST /webhooks/stripe` already wired.)

## 10. UI

Extend `ColtWeb.Account.EmailAccountsLive`
(`lib/colt_web/live/account/email_accounts_live.ex`) with a **"Buy domains"**
wizard (source → volume calculator → AI-suggested available-domain checklist →
Stripe redirect) and a **warming-status card** with a countdown on return. Must
match Calm Pro (bounded cards, `docs/design.md`, `priv/design_demos/d1-calm.html`).

## 11. Phase plan (one phase at a time, single-line commits)

1. **Data model** + migrations (`SendingDomain`, `DomainOrder`, `EmailAccount`
   fields, `daily_quota` → 20).
2. **`Colt.Registrar` + `SuggestDomains`** — OpenRouter naming + availability,
   verifiable standalone against the RR OT&E sandbox.
3. **One-off Stripe checkout** + `DomainOrder` + webhook → `Registrar.register`.
4. **Provisioning adapter (Mailpool)** + `Nylas.connect_custom` + DNS.
5. **Mailivery** enroll + warmup gate in scheduler + `CheckWarmup` cron.
6. **Buy-domains LiveView** + warming status.

Phases 1–3 can be built against the RR sandbox with a stubbed provisioning
adapter **without** any live vendor account. Phases 4–5 gate on the vendor
verifications below.

## 12. Prerequisites the user must do (can't be done in-code)

- **Mailpool:** request API docs, **confirm raw IMAP/SMTP creds per mailbox are
  exposed**, get an API key. Gates Phase 4 (else swap to Mailreef).
- **Realtime Register:** open free OT&E account → confirm the real `.ee`
  wholesale price + get sandbox API key; budget for the `.ee` admin-contact
  formality (signature or paid local-contact ~€12) under Täp OÜ.
- **Mailivery:** account + API key; ask DPA whether the warming pool is
  EU-constrained.
- **Nylas:** confirm BYO custom-auth is enabled on the current plan.

New `runtime.exs` blocks (env-read, app-level — no per-user keys): `:realtime_register`,
`:mailpool`, `:mailivery`. Stripe/Nylas/OpenRouter already configured.

## 13. Decision

**Scoped, not building yet.** Stack and product decisions are settled; the
blockers are the four vendor verifications in §12 (chiefly: does mailpool hand
over raw mailbox credentials). Pick up at Phase 1 against the RR sandbox once
those are confirmed. This doc is the pickup point.

---

### Source references (verified 2026-07-11)
- Realtime Register API: `https://dm.realtimeregister.com/docs/api/` · OT&E `https://api.yoursrs-ote.com/`
- internet.ee registry (`.ee` €6 flat, accreditation): `https://www.internet.ee/registripidaja`
- Zone API (management-only, can't register): `https://api.zone.eu/v2`
- Mailpool: `https://www.mailpool.ai/features` · `https://www.mailpool.ai/pricing` (API docs request-only)
- Mailreef (alt provisioner): `https://www.mailreef.com/email-api`
- Mailivery API: `https://mailivery.readme.io/reference/mailivery-api-introduction` · pricing `https://mailivery.io/pricing`
- MailReach (alt warmup): `https://docs.mailreach.co/`
- Nylas v3 BYO auth: `https://developer.nylas.com/docs/v3/auth/bring-your-own-authentication/` · pricing `https://www.nylas.com/pricing/`
