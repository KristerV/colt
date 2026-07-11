# Contact acquisition — owner/decision-maker emails

**Status: RESEARCHED, DEFERRED (2026-07-11).** Not building now. A few clients
asked for it, but the honest move is to do outreach, land a real client base,
and let *them* tell us what they need before we build a targeting system on
spec. This doc captures the research and the design we landed on so it's ready
to pick up if demand materialises.

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
- **No bounce-probing by sending.** Sending-to-test means you've already emailed
  them and burned sender reputation. The verifier (MX/SMTP check) is the
  non-spammy version of that probe. It's ~85%, not 100% — accept that.
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

The order is **user-defined** — Owner-after-Role is as valid as Role-after-Owner.
There is no fixed hierarchy. This resolves the two UX objections that killed the
naïve dropdown:
- *"Waterfalling to a title needs the title"* → the title field lives **inside**
  the Role card, only shown for that step type. Local, not global.
- *"What if they want owner after a title?"* → they order the cards however they
  like. The list *is* the priority.

### Why it stays simple
- **Defaults to one card.** 99% of users set a single target and never add a
  fallback — visually identical to one dropdown, zero added burden.
- **Progressive disclosure.** The stack grows only when someone deliberately
  builds a chain (`+ Add fallback`).
- **Presets** ("Founder-first", "By title", "Just get in the door") avoid the
  blank-canvas problem — pick one, tweak if you care.
- Renders as bounded cards with gaps — native to the Calm Pro design system.

```
Who should we reach?
┌────────────────────────────────────┐
│ 1  Owner / founder              ⋮⋮ │   ← default: just this card
└────────────────────────────────────┘
              ↓ if not found
┌────────────────────────────────────┐
│ 2  Role   [ Head of Sales  ▾ ]  ⋮⋮ │   ← title lives inside the Role card
└────────────────────────────────────┘
              ↓ if not found
┌────────────────────────────────────┐
│ 3  Generic inbox (info@)        ⋮⋮ │
└────────────────────────────────────┘
        [ + Add fallback ]
```

### Architectural payoff
An **"owner-only, no fallback"** ICP **short-circuits the enrichment funnel**:
registry name → domain → guess → verify. No chromium, no AI contact extraction.
The cheapest path and the simplest path are the same path — offering owner
targeting *removes* load for that segment rather than adding it.

### Provenance on the contact
A `confidence` / `source` enum on the person record, surfaced as one chip on the
card: `verified` (green) / `guessed` (amber) / `registry_unverified` (grey).
Storing the flag was never the complexity; the acquisition strategy above is.

## 5. What already exists in the codebase (reference)

The generic-inbox rung is already built:

- **`Company.generic_email`** — `lib/colt/resources/company.ex` (single company
  email field; set via `:upsert_details` / `:set_generic_email`).
- **EE import** captures it from the registry EMAIL contact-means —
  `lib/colt/services/ingest/ee/rik/company_details.ex` (`pick_active .. "EMAIL"`).
  No other country importer captures a company email.
- **Landing scrape** regexes `info@/contact@/hello@/sales@/hi@/kontakt@/myynti@`
  on the company's own domain — `lib/colt/services/enrichment/extract_generic_email.ex`,
  written back in `lib/colt/jobs/enrichment/fetch_landing.ex`.
- **`Colt.Resources.Person`** — currently models **scraped website contacts
  only** (name/title/email/phone, linked via `source_page`). It does **not** yet
  model registry officers/owners. The deep contact-page AI extractor explicitly
  *skips* generic mailboxes.
- **`verify_email`** (`lib/colt/jobs/enrichment/verify_email.ex`, MyEmailVerifier)
  verifies a picked person's email today — the guess-resolver would reuse it.

### If/when this is built, the deltas are roughly
1. Per-market registry **person** ingest (board/owner names) → `Person` with
   `source: :registry` + a role. Country-agnostic model; one parser per market,
   prioritised by client demand. Free for EE/FI/LV/LT/NO/DK.
2. `confidence` / `source` enum on `Person`.
3. Candidate email generator + verifier resolver (§3).
4. Ordered target-step list on the ICP + the three resolver paths (§4).
5. Branch: owner-only ICP skips scraping jobs.

## 6. Decision

**Deferred.** The mechanism scales up (Role rung serves mid-market) and out
(more registries), so it isn't a small-client-only investment — but building a
targeting system for a handful of maybe-interested clients is premature. Do
outreach first, get a real client base, then let observed demand drive which
rungs and which markets get built. This doc is the pickup point.
