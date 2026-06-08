# Email provider & Google verification — decision record

Reference notes on the email-integration provider choice and the Google OAuth /
CASA verification problem. Captured so we don't re-research this. Companion to
`docs/email-sending.md` (§0 pins the active provider).

**Last researched:** 2026-06-08.

---

## TL;DR / current stance

- **Now:** stay on **Nylas v3, EU region** with **our own Google OAuth app** to
  get moving. This means *we* owe Google's verification + CASA for production
  Gmail at scale — fine while small (see the 100-user cap below).
- **Compromise path:** the Google paperwork is a **standalone, cheap** service —
  a Google-authorized **CASA assessor** (TAC Security ~**$540/yr**). It is not
  bundled into any email API; you can buy it separately for *any* setup.
- **Stronger eventual option:** **EmailEngine self-hosted** (full EU control,
  flat pricing, raw threading/bounce fidelity) **+ a TAC CASA assessment**. This
  gives EU residency *and* outsourced paperwork without aggregator lock-in.

---

## The problem, in two layers

"EU compatible" and "Google paperwork" are **separate** concerns. Don't conflate.

### Layer 1 — Google verification / CASA (global, scope-driven)

Gmail OAuth scopes have three tiers:

- **Non-sensitive** (`userinfo.email`, `profile`, `openid`) — no pain. Can't send mail.
- **Sensitive** (`gmail.send`, `gmail.compose`, `gmail.labels`, metadata) — app
  verification (branding/privacy-policy review) but **no security audit**.
- **Restricted** (`gmail.readonly`, `gmail.modify`, `https://mail.google.com/`,
  settings) — verification **+ annual CASA security assessment**.

**We read replies, so we need restricted scopes → CASA applies.** No way around
that *if* we own the OAuth app and read mailbox content.

CASA is **global** — it keys off the scopes requested, not where we or our users
are. The EU has no bearing on it.

Tiers of CASA: **Tier 1** = free self-questionnaire (insufficient for Gmail
restricted). **Tier 2** = authorized-lab DAST scan + remediation + Letter of
Assessment — **this is what Gmail restricted scopes require.** **Tier 3** = full
manual pentest, only for the highest-risk cases — *not* us.

**The 100-user escape hatch:** an *unverified* app can run indefinitely with up
to **100 users** on restricted scopes. No CASA, no cost — the only penalty is the
"unverified app" warning screen at connect. Fine while we're small; the paperwork
only becomes mandatory past 100 Gmail users.

**B2B escape hatch:** if a customer is on **Google Workspace**, their admin can
**allowlist/trust** our app domain-wide. Apps only used inside orgs that trust
them don't need public verification or CASA at all.

**Microsoft/Outlook:** **no CASA equivalent.** Publisher verification is light.
Graph supports an EU Data Boundary. Lean on Outlook where possible.

### Layer 2 — EU data residency / GDPR (about where data lives)

"GDPR compliant" is **not one checkbox**. It decomposes into:

1. **A signed DPA** — provider is our *processor*, we're the *controller*. No DPA
   = unusable for EU PII. This is the load-bearing artifact.
2. **Lawful transfer basis — NOT necessarily EU-soil storage.** GDPR allows data
   to leave the EU with adequate safeguards: an **adequacy decision** (the UK has
   one — so Nylas storing in the UK is legal) or **SCCs / EU-US Data Privacy
   Framework** for US providers. "Stored in the US" can still be compliant.
3. **Sub-processor transparency** — published list + change notice.
4. **Data-subject rights** — erasure, portability, 72h breach notification.

So we need: **a DPA + a lawful-transfer basis.** EU-*soil* storage is only
required if a specific customer contract demands it (some regulated buyers do).

---

## The core tradeoff (this is the key insight)

You largely **cannot** have both "no Google paperwork" *and* "full self-controlled
EU residency" for free — they pull opposite directions:

| Optimize for… | …consequence |
|---|---|
| **No Google paperwork** (inherit provider's CASA) | users authorize the *provider's* OAuth app → their infra touches the data → EU residency depends entirely on the provider offering an EU region |
| **Full self-controlled EU residency** (self-host) | you own the OAuth app → *you* owe CASA |

**BUT** — a paid CASA assessment (~$540/yr, below) collapses this. For that price
you *can* self-host (own EU control) *and* outsource the paperwork. The "can't
have both" only holds if you insist on doing it for free.

---

## Provider landscape (researched 2026-06)

### Group A — inherit their verification (no Google paperwork), hosted only

- **Nylas** *(current choice)* — mature threading (`thread_id`) + bounce/delivery
  events, hosted OAuth, published DPA, SOC 2, ISO 27001. **Caveat:** the "EU"
  region actually stores in the **UK** (GDPR-legal via UK adequacy, but not
  EU-soil). v3 migration is heavy; costs rising. Most GDPR-documented of the bunch.
- **Aurinko** — cheapest (~$1/acct/mo), owns OAuth app, explicit `replyBounce`
  webhook events, mature bidirectional sync (BrightSync). **Caveat:** public
  compliance posture is **thin** — privacy policy mentions no DPA, no EU
  residency, no SOC2; operating company is **Yoxel (US)**. EU residency
  unconfirmed — would need to be forced out of sales (`compliance@yoxel.com`).
- **Unipile** — EU-hosted, inherits CASA. **RULED OUT:** we used it before;
  threading was garbage (had to reverse-engineer a lot) and bounce detection was
  poor. Origin is messaging (LinkedIn/WhatsApp), email bolted on.

### Group B — you own the OAuth app (you owe CASA), but full data control

- **EmailEngine** — **self-hosted**, flat annual pricing (unlimited accounts),
  **stores only metadata** (message content fetched on-demand from the mailbox,
  never copied to a third party). Native IMAP/SMTP + Gmail API + Graph. Run it in
  any EU region → EU residency becomes "which datacenter do I deploy in." For
  Gmail-API connections you bring your own creds (→ CASA), but **IMAP/SMTP
  connections skip the Gmail API entirely → no CASA for those users.** Strongest
  candidate for EU control + threading/bounce fidelity + cost.
- **Nango** — SOC 2 Type II + GDPR + HIPAA, **self-hostable** for full isolation.
  You own the OAuth app (→ your own verification). Integration infra, 800+ APIs.

There is **no** "inherit-CASA + EU-soil + great-threading" unicorn. The market
splits into these two camps; bridging them is what the CASA assessor is for.

---

## The CASA assessor option (the "paperwork as a service")

CASA is decoupled from any email API — it's an assessment you commission from a
Google-authorized lab. Real Tier 2 pricing (the tier Gmail needs):

| Assessor | Tier 2 price (annual) |
|---|---|
| **TAC Security** (Google's *preferred* lab) | **$540** baseline → $1,800 premium |
| Leviathan | $800–1,200 |
| NetSentries | $900–1,500 |
| NCC Group | $1,200+ |
| Bishop Fox | $1,500+ (premium end) |
| KPMG / DEKRA / Orange | enterprise/custom — ignore |

**TAC Security ~$540/yr** includes a functional DAST scan + **guided
remediation** + 2-to-unlimited re-scans, online portal (`casa.tacsecurity.com`),
1–3 week turnaround. Google negotiated a discounted preferred rate with them.

**Why the scary $8k–40k figures on Reddit/Medium are misleading:** they conflate
(a) **Bishop Fox / big-firm** premium quotes, (b) **Tier 3** full pentests (not
required for standard Gmail scopes), and (c) general alarmism. Standard Gmail
restricted-scope **Tier 2 via TAC is ~$540/yr.**

**Split of responsibility:**
- **Assessor handles:** the security assessment — scan, findings, guided
  remediation, re-scan, and the **Letter of Assessment (LOA)** that satisfies
  Google. (The part that used to "cost $40k".)
- **Still ours (free, just tedious):** OAuth **branding verification** — consent
  screen, verified domain, privacy-policy URL, demo video of scopes in use.

Re-validation: **annual** (every 12 months from LOA approval) as long as scopes
are unchanged.

---

## Recommended path forward

1. **Now:** Nylas v3 EU + our own OAuth app. Run under the **100-user unverified
   cap** while small. Steer customers toward **Outlook** and Google **Workspace**
   (both dodge CASA). $0 until we have real revenue.
2. **When approaching 100 Gmail users / needing production verification:** buy a
   **TAC Security Tier 2** assessment (~$540/yr). Cheap, decoupled, done.
3. **If/when Nylas cost, UK-storage, or threading/cost friction justifies a
   switch:** evaluate **EmailEngine self-hosted** (EU region of our choice) +
   TAC CASA. Best EU control + cost + threading fidelity, no aggregator lock-in.

## Open questions to confirm before committing money

- **Nylas EU region physical location** — docs are inconsistent (US vs UK vs EU).
  Confirm actual storage location and whether UK adequacy satisfies our buyers.
- **Aurinko** — if ever reconsidered: force a written answer on DPA, EU
  residency, SOC2, and transfer basis (`compliance@yoxel.com`).
- **Whose name shows on the OAuth consent screen** for any "inherit-CASA"
  provider — that's the mechanism that shifts the burden. Get it in writing.
- **EmailEngine threading/bounce model** — validate it actually beats what burned
  us on Unipile before betting on it.

## Sources

- Nylas: [data residency](https://developer.nylas.com/docs/dev-guide/platform/data-residency/),
  [GDPR](https://developer.nylas.com/docs/support/general-data-protection-regulation/)
- Google: [restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- CASA pricing: [SwitchLabs](https://www.switchlabs.dev/post/casa-tier-2-tier-3-security-review-providers-pricing-and-the-cheapest-option),
  [TAC Security](https://casa.tacsecurity.com/site/home),
  [App Defense Alliance assessors](https://appdefensealliance.dev/casa/casa-assessors)
- Alternatives: [EmailEngine](https://emailengine.app/),
  [Nango comparison](https://nango.dev/blog/best-integration-platform-for-mail-and-calendar-integrations/),
  [Aurinko privacy](https://www.aurinko.io/privacy/)
