# Contact acquisition — owner/decision-maker emails

**Status: BUILDING — EE first (2026-07-14).** Un-deferred. Measuring the actual
EE import overturned the premise behind the deferral: this is not a
small-client nicety, it's the shape of the Estonian market. **97% of EE
companies carry a registry contact email; only 6.5% carry a registry website.**
The existing enrichment funnel is built for the minority that has a site; for
the EE SME long tail the registry email *is* the channel.

Scope of the build: the **owner rung, step 1 only** — classify the registry
email personal-vs-generic and use it. Step 2 (registry *name* → guess → verify)
is blocked on a person-name import that doesn't exist yet; see `docs/todo.md`.

**Status: RESEARCHED, DEFERRED (2026-07-11).** *(superseded — kept for context)*
Not building now. A few clients asked for it, but the honest move is to do
outreach, land a real client base, and let *them* tell us what they need before
we build a targeting system on spec.

Scope: how to reach a **person** at a target company (owner, decision-maker by
title, or a generic inbox), and what email address to send to. This is the
"who do we email" dimension. Company identity / revenue / headcount lives in
`docs/data-sources.md` and `docs/countries/`; this doc does not repeat it.

---

## 1. The core finding

**No European business registry publishes personal email addresses. Anywhere.**
Not EE, not any market we support. What registries *do* publish — publicly and
mostly free — is **names + roles** of board members and owners.

So there is no "fetch the owner's email" feed to buy or scrape. The only path is:
**registry name → guess the address on the company domain → verify.** Email is
always *derived*, never *given*.

For a typical small OÜ / AS / Oy the sole **board member is the owner**, so the
registry name is exactly the person the client wants — we just have to construct
and verify their address.

## 2. What each market exposes (person data, free tier)

Verified 2026-07-11 via registry open-data docs. "Names" = first + last of
board members / representatives / shareholders.

| Market | Owner/board names? | Access | Emails? | Notes |
|---|---|---|---|---|
| EE 🇪🇪 | ✅ board, shareholders, UBOs | Free bulk JSON/XML — **same open data we already ingest** | ❌ | Since 2024-11, open data no longer includes personal ID code (isikukood). Names only. |
| FI 🇫🇮 | ✅ board + date of birth | Free PRH BIS API | ❌ | API docs explicitly state no email / no phone. |
| LV 🇱🇻 | ✅ officers (first name + surname) | Free open data (data.gov.lv CKAN) | ❌ | Executive/supervisory board, liquidators, representatives. |
| LT 🇱🇹 | ✅ directors / managers | Free daily CSV + public portal | ❌ | Members of sole & collective management bodies. |
| NO 🇳🇴 | ✅ board roles + birth date | Free Brreg *roller* API | ❌ | Cleanest API in the region. Use limited to business-activity roles. |
| DK 🇩🇰 | ✅ participants / directors / board | Free bulk (datahub, registration required) | ❌ | 1.7M+ participants incl. owners/directors/board. |
| SE 🇸🇪 | ✅ board + CEO | Names free in basic search + free weekly HVD bulk; **full API ~SEK 6250** | ❌ | Same OAuth2 gate as the SE revenue ingest (see `countries/se.md`). |
| PL 🇵🇱 | ⚠️ official API **anonymises** to `L******`; full names only by parsing the PDF extract | Free but awkward | ❌ | Post-eKRS-2024. Consistent with PL being deferred for financials too. |

**Free person-names are realistic for the six EE/FI/LV/LT/NO/DK today.** SE costs
money or needs the human-issued creds; PL needs PDF-extract parsing.

### Beneficial-owner (UBO) caveat
The 2022 CJEU ruling tightened *interactive* UBO access to "legitimate interest"
across EE/DK/others during 2025. This does **not** affect what we need: **board
members and shareholders stay fully public in bulk**, and for small companies
that's the owner anyway. Don't design around UBO.

## 3. Email construction & verification

Registry gives a name; we build candidates and let the verifier pick one.

- **Candidates per person:** `first@domain.tld` **and** `first.last@domain.tld`
  (optionally `f.last@`). Founders very often go by first-name-only, so `first@`
  must be tried, not just `first.last@`.
- **Resolve, don't surface.** Run each candidate through the verifier
  (MyEmailVerifier — already wired as `verify_email`); the one that passes goes
  in TO. This is not a user-facing choice.
- **One person = one address in TO.** Never put two guesses in TO — same human,
  reads as a mail-merge misfire, hurts deliverability. If none verify: either
  send to the single most-likely (`first.last@`) as a flagged guess, or fall
  through to the next target. That's one global setting, not a per-contact field.
- **No Gmail / personal-domain guessing.** Hit rate is poor, unverifiable, and
  spammy. Domain-guess only; no domain → fall through.
  - **Exception — registry-given addresses (2026-07-14).** The rule above governs
    *guessing*. It does not govern an address the registry **hands us**. Measured
    on the EE import: **66% of registry contact emails are on free domains**
    (gmail.com, mail.ru, hot.ee). These aren't guesses — they're the address the
    owner themselves filed with the registrar, and for an EE micro-OÜ they are
    frequently the only contact channel that exists. Excluding them would cut the
    owner rung to ~34% of companies and gut the feature. So: **a free-domain
    address is usable when it is registry-given AND classified personal AND
    verifies.** It is never usable as a guess target — we never construct
    `first.last@gmail.com`.
- **No bounce-probing by sending.** Sending-to-test means you've already emailed
  them and burned sender reputation. The verifier (MX/SMTP check) is the
  non-spammy version of that probe. It's ~85%, not 100% — accept that.
- **Catch-all comes from the vendor — don't infer it.** MyEmailVerifier already
  returns `"Catch-all"` as a `Status` value distinct from `"Valid"`. Do **not**
  detect catch-all by probing two candidates and seeing if both pass; just read
  the field. `verify_email.ex` historically collapsed `"Catch-all" -> :valid`,
  which is **provenance-dependent and only safe for scraped addresses**: a
  catch-all domain says nothing about whether a *guessed* address exists, but a
  *scraped* address was literally published on the company's own contact page.
  Hence: catch-all + guessed → unusable; catch-all + scraped/registry-given → usable.
- **Domain discovery** already exists in the enrichment funnel (registry website
  field + Google fallback). No domain and no generic inbox → that company simply
  has no reachable contact. Honest, and fine.

## 4. Targeting UX — the "waterfall"

The client's real need is an **ordered list of preferences** for who to reach —
this is the "waterfall enrichment" pattern (Clay/Apollo). Naïvely this looks
like a settings matrix; it isn't, if modelled as an ordered stack of typed
steps that defaults to one step.

### Model: ordered list of typed target steps
Each step has a **type**, and the type decides both its parameters and which
funnel path resolves it:

| Step type | Param | Resolves via | Data source |
|---|---|---|---|
| Owner / founder | none | registry person + guess + verify | `source: :registry` |
| Role | a **title** (e.g. "Head of Sales") | scraped contact extraction (existing enrichment) | `source: :scraped` |
| Generic inbox | none | landing-page `info@` regex (existing) | `Company.generic_email` |

**Revised 2026-07-14 — the order is FIXED, not user-defined.** The drag-to-reorder
stack above was over-built. Nobody wants `info@` ahead of the owner; the ladder
owner → title → generic is strictly decreasing in value, so the only real choice
is **which rungs you're willing to land on**. That's three checkboxes, not a
sortable list:

```
Who should we reach?
┌────────────────────────────────────────────┐
│ [x] Owner                                  │
│ [x] Job title   [ Head of Sales         ]  │
│ [ ] Generic inbox (info@)                  │
└────────────────────────────────────────────┘
        tried in that order, top to bottom
```

- The title input lives inside its row and is only meaningful when that box is
  ticked (it maps to the existing `campaign.target_job_title`).
- All three unticked = no reachable contact; the campaign can't enrich.
- **Cost falls out of the order for free.** Owner and generic are both *cheap* —
  owner resolves from `registry_email` (no scraping at all) and generic resolves
  from the landing page we already fetched. Only the **title** rung needs the
  expensive contact-page subchain (`PickContactPages` → `ScrapeContactPage` →
  `ExtractContacts`). So an owner-hit short-circuits the costly path, and an
  owner+generic campaign never scrapes contact pages at all.

### The "must have a website" checkbox
Separate from the rungs, and default **on**. Domain discovery already tries the
registry `website_url` then falls back to a Google search
(`CheckWebsite` → `GoogleSearch`), so this checkbox only governs the case where
**Google also finds nothing**:
- **On** (default) → terminate `:no_website`, exactly as today.
- **Off** → don't fail. Skip the `website` and `icp` pills as `:skip` and go
  straight to contact resolution on `registry_email`. Needs a warning in the UI:
  with no site there is no `ai_summary`, so **the ICP check cannot run** and
  targeting rests on the structured filters (industry, revenue, headcount) alone.

ICP is still checked whenever a site *is* found, regardless of this checkbox.
Note `MatchICP` already silently auto-passes when the summary is empty
(`match_icp.ex:36-40`); that bypass must become explicit and gated on this
checkbox, and mark the pill `:skip` rather than `:done`.

### Architectural payoff
An **"owner-only"** ICP **short-circuits the enrichment funnel**: registry email →
classify → verify. No chromium, no AI contact extraction. The cheapest path and
the simplest path are the same path — offering owner targeting *removes* load for
that segment rather than adding it.

### One human, one email, per campaign
A single person often registers several companies — on the EE import **180
addresses are the registry contact for 2+ companies, covering ~5% of rows**. The
owner rung would otherwise pick that person once per company and send them four
near-identical cold emails in one campaign, which reads as spam because it is.

`picked_person_id` **cannot** detect this: `Person` belongs to a company, so the
same human is a separate row per company and the ids never collide. The
comparison has to be on the address. Hence `CampaignCompany.picked_email`
(lowercased, denormalised off `Person`) plus
`identity :campaign_picked_email, [:campaign_id, :picked_email]`.

- Postgres treats NULLs as distinct, so the thousands of not-yet-resolved rows in
  a campaign don't collide with each other. No partial index needed.
- `ContactDedup.taken?/3` is a **pre-check that saves churn, not the guarantee** —
  two jobs racing on the same address both pass it. The unique index holds the
  line; the loser handles the constraint error.
- **Gotcha:** Ash reports a composite-identity violation against the identity's
  *first* field (`:campaign_id`), not the colliding one. `identity
  :campaign_company` is also `[:campaign_id, …]`, so the field cannot tell them
  apart — `ContactDedup.duplicate_error?/1` matches on the **constraint name**.
  `contact_dedup_test.exs` pins both facts.
- A duplicate is a **rung miss, not a dead end**: the company drops to its own
  generic inbox rather than being written off. Only an exhausted ladder ends as
  `:no_contacts`, with a reason naming the address and the company already
  holding it.
- Deliberately **not** a new status. `:no_contacts` already maps to
  `stage_frontier(2, :fall)` — the contact pill, exactly where a duplicate is
  found — and a dedicated `:duplicate_contact` would have to be threaded through
  ~12 switch sites (buckets, labels, pills, usage counting, the failed-count
  aggregate) to say what the reason string already says.

### Provenance — on the Company, not an early Person
The earlier draft put a `source` / `confidence` enum on `Person`. **Rejected
2026-07-14:** it forces a `Person` row into existence during ingest/classification,
which is the wrong phase of the pipeline — `Person` is an enrichment-time artifact
tied to a `source_page`. Instead, **widen `Company` and save more data**:

| Column | Meaning |
|---|---|
| `registry_email` | raw contact email from the registry import. EE ingest writes **here**, no longer into `generic_email`. |
| `registry_email_kind` | `:personal \| :generic` — cached AI verdict. `nil` = not yet classified. |
| `generic_email` | unchanged meaning: the `info@` rung. Now written **only** by the landing scrape. |

This also kills a latent bug structurally rather than with a guard:
`fetch_landing.ex:98-100` currently **overwrites** the registry email with a
scraped `info@`, with no `generic_email_source` to tell them apart (unlike
`website_url`, which has `website_source`). Once the registry address lives in its
own column, the scrape has nothing to clobber.

## 5. What already exists in the codebase (reference)

The generic-inbox rung is **captured but never used** — `generic_email` is written
in exactly two places (`fetch_landing.ex:99`, `company_details.ex:81`) and read by
no job and no LiveView. Wiring it to a rung is new work, not reuse.

- **`Company.generic_email`** — `lib/colt/resources/company.ex:356` (single field;
  set via `:upsert_details` / `:set_generic_email`).
- **EE import** captures it from the registry EMAIL contact-means —
  `lib/colt/services/ingest/ee/rik/company_details.ex:81` (`pick_active .. "EMAIL"`).
  No other country importer captures a company email.
- **Landing scrape** regexes `info@/contact@/hello@/sales@/hi@/kontakt@/myynti@` on
  the company's own registrable host —
  `lib/colt/services/enrichment/extract_generic_email.ex:9`, written back in
  `fetch_landing.ex:98`. **Regex-only today; people are creative with generic
  prefixes (`tere@`, `pood@`, `kontor@`), so this needs an AI second pass when the
  keyword list misses.**
- **`Colt.Resources.Person`** — models **scraped website contacts only**
  (name/title/email/phone via `source_page`). `name` is nilable;
  `email_verification_status` is `one_of: [:valid, :invalid]` and needs a third
  value for catch-all. Does **not** model registry officers.
- **`verify_email`** (`services/enrichment/verify_email.ex:12`, MyEmailVerifier)
  returns `{:ok, :valid | :invalid}`, collapsing `"Catch-all" -> :valid` at
  lines 49-58. The vendor also returns `Role_Based`, `Disposable_Domain`,
  `Free_Domain`, `Greylisted` — all currently discarded.
- **`Colt.Services.Scrape.Fetch.run(url, opts)`** (`services/scrape/fetch.ex:17`) is
  a pure function of a URL with no Oban/CampaignCompany coupling — already reused
  standalone by `services/sending/pitch_summary.ex:94`. Reusable as-is.
- **Pill state `:skip` already exists and renders** (`components/funnel.ex:289,605`;
  `broadcast.ex:10`) — the no-website path needs no new pill machinery.

### Build order (EE, step 1)
1. `Company`: add `registry_email` + `registry_email_kind` (+ migration, + backfill
   copying EE `generic_email` → `registry_email`); EE ingest writes the new column.
2. AI classifier: registry email → `:personal | :generic`, cached on the company.
   Runs per-campaign-company at enrichment time, not over 250k rows at import.
3. `ExtractGenericEmail`: keyword match first, AI second pass on miss.
4. Verifier: widen to `{:ok, :valid | :catch_all | :invalid}`; `Person`
   `email_verification_status` gains `:catch_all`. Catch-all is acceptable for a
   registry-given or scraped address, fatal for a guessed one (§3).
5. ICP UI: three rung checkboxes + `target_job_title` inside the title row, plus
   the "must have a website" checkbox and its warning.
6. Resolver: try owner → title → generic in fixed order, inserted **before**
   `PickContactPages` so an owner hit skips the contact-page subchain entirely.

### Deferred to `docs/todo.md`
Step 2 of the owner rung — registry **person-name** ingest (board/owner names) →
guess `first@` / `first.last@` on the company domain → verify. Blocked: the RIK
download (`ingest/ee/rik/download.ex:17-36`) fetches three file families and the
personnel/representation dump is not among them; nothing in `rik/` touches
`Person`. Note this step is **inapplicable to the 66% on free domains** — there is
no company domain to guess on — so it only extends reach for the company-domain
minority.

## 6. Decision

**Building EE step 1 now (2026-07-14).** The 2026-07-11 deferral assumed this was
a targeting system for a handful of maybe-interested clients. The EE numbers say
otherwise: 97% registry-email coverage vs 6.5% registry-website coverage means the
owner rung isn't a niche add-on, it's how you reach the Estonian SME long tail at
all. Two of the six build items (catch-all collapse, destructive overwrite) are
bug fixes worth doing regardless. Step 2 stays deferred on cost, not on doubt.

## 6. Decision

**Deferred.** The mechanism scales up (Role rung serves mid-market) and out
(more registries), so it isn't a small-client-only investment — but building a
targeting system for a handful of maybe-interested clients is premature. Do
outreach first, get a real client base, then let observed demand drive which
rungs and which markets get built. This doc is the pickup point.
