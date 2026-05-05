# Colt — Lead Enrichment Tool

A LiveView app that turns a free-text ICP + a market filter into a CSV of validated B2B contacts ready for Instantly.ai.

## 1. Overview

Pipeline:

1. User describes their ICP and target job title.
2. App pulls a candidate list from the public Estonian registry (rik.ee). Other markets (FI, LV, LT, SE, NO) are deferred — see §11.
3. User narrows with structured filters (industry, region, founded year, revenue, employees, growth).
4. Pipeline enriches up to 1000 companies in parallel: validate website, scrape, summarize, match against ICP, find named contacts, validate emails.
5. User exports an Instantly-format CSV.

Stack: Elixir, Phoenix LiveView, Ash, Postgres, Oban, Wallaby, Req+Floki, OpenRouter (GLM 4.7 + Claude 4.5 Sonnet), Google Custom Search.

## 2. Auth & multi-tenancy

- Magic-link auth (Ash Authentication). Open signup.
- Each `User` owns their own `Campaign` records.
- Companies, Pages, Persons, AnnualReports are **globally shared** (no `user_id`). Two users targeting the same company benefit from one another's enrichment.
- A `Campaign → Company` relationship lives in a join resource (`CampaignCompany`) so per-campaign decisions (rejected / included in export) don't pollute shared data.

## 3. Data sources

### 3.1 Registry ingestion (background, runs nightly)

- **Estonia**: rik.ee Avaandmed
  - Docs: https://avaandmed.ariregister.rik.ee/et/ariregistri-avaandmete-api/api-teenuste-tutvustus
  - Companies CSV (`ettevotja_rekvisiidid`)
  - Annual reports / majandusaasta aruanded (XBRL or extracted financial summary)
  - **Contract**: API access agreement is already in place. Credentials live in env / settings — confirm with the user before regenerating.

**v1 ships Estonia only.** Finland (PRH Avoindata + Tilinpäätöstiedot), Latvia, Lithuania, Sweden, and Norway are deferred — see §11. The data model still carries a `market` column so adding a new registry is additive.

Ingestion is an Oban cron job (daily at 03:00 UTC). It upserts companies and the last 3 fiscal years of revenue/employees per company. After upsert, a `compute_growth` action fills:

- `revenue_latest` (EUR)
- `employees_latest`
- `revenue_growth_bucket` ∈ `{:declining, :stagnant, :slow, :growing_2x, :growing_10x}`
  - declining: latest < prev (UI label "Shrinking")
  - stagnant: |Δ| ≤ 5%
  - slow: 5%–100% (UI label "Growing · slow")
  - growing_2x: 100%–900% (UI label "Growing · 2×")
  - growing_10x: > 900% (UI label "Growing · 10×")
  - companies with <2 years of reports: `nil`

**Risk / open question**: rik.ee XBRL parsing depth needs a spike before sprint start. If the open data feed turns out to omit revenue, fallback is teatmik.ee/inforegister.ee scraping — flagged but out of scope for v1.

### 3.2 Third-party services & contracts

Authoritative list of every external service Colt talks to. Procedure for adding new ones is in `docs/phases.md` → "Working with third-party services".

| Service | Phase | Docs | Credentials | Contract status |
|---|---|---|---|---|
| **rik.ee Avaandmed** | 1 | https://avaandmed.ariregister.rik.ee/et/ariregistri-avaandmete-api/api-teenuste-tutvustus | env / app config | **In place** — API access agreement signed. Don't regenerate without asking. |
| **OpenRouter** | 4a | https://openrouter.ai/docs | env / app config (`OPENROUTER_API_KEY`) | App-level account. Pay-as-you-go. |
| **Google Custom Search API** | 4a | https://developers.google.com/custom-search/v1/overview | env / app config (`GOOGLE_CSE_API_KEY`, `GOOGLE_CSE_ENGINE_ID`) | App-level account. Free tier 100 queries/day, then $5/1000. |

## 4. Domain (Ash resources)

```
User
  has_many :campaigns

Campaign
  belongs_to :owner, User
  attrs: name, icp_description, target_job_title, market (:ee for v1; :fi/:lv/:lt/:se/:no reserved),
         filters (jsonb: industries, regions, founded_year_range,
                  revenue_range, employees_range, growth_buckets, status_filter),
         status (:draft | :collecting | :enriching | :complete | :archived),
         finalized_at
  has_many :campaign_companies

CampaignCompany   # join, per-campaign decisions
  belongs_to :campaign
  belongs_to :company
  attrs: status (:pending | :scraping | :rejected | :no_website | :enriched | :failed),
         rejection_reason, included_in_export (bool, default true)

Company           # globally shared
  identity :registry_code on [:registry_code, :market]
  attrs: registry_code, market, name, region, industry_code, status,
         website_url, website_source (:registry | :google | :manual),
         generic_email, ai_summary, last_enriched_at
  has_many :annual_reports
  has_many :pages
  has_many :persons

AnnualReport
  belongs_to :company
  identity on [:company_id, :year]
  attrs: year, revenue_eur, employees, source (:rik for v1)

Page
  belongs_to :company
  identity on [:company_id, :path]
  attrs: path, title, in_navigation, markdown, fetched_at, fetcher (:static | :wallaby)

Person
  belongs_to :company
  belongs_to :source_page, Page
  attrs: name, title, email, phone, validated_in_markdown,
         matches_target_title (computed per-campaign — see §6.9)
```

Notes:
- All resources use `default_accept` + `defaults [:read]` per project convention.
- `Resource.read` not used; use `Ash.get/2` or named actions.
- Loads via `load:` option on the action, not separate `Ash.load!`.

## 5. Views (LiveView)

All views are LiveViews under `/campaigns/:id/...`. View 0 is `/campaigns/new`. Navigation is wizard-style: forward-only until view 4. After view 4 the campaign is read-only.

### 5.1 View 0 — New campaign
- Single field: `name`.
- Right-side "Recent" sidebar: the user's last 4 campaigns. Per row: name, `done_count / total_count` (mono), relative time. Hairline rules between rows. Clicking a row navigates to that campaign's view 4.
- Submit creates `Campaign{status: :draft}`, redirects to view 1.

### 5.2 View 1 — ICP
- One textarea: `icp_description` (max 2000 chars, character counter top-right).
- One single-line text input: `target_job_title` — free text, e.g. "CTO" or "Head of Engineering". Single value per campaign.
- Both saved on blur (and on Next).

### 5.3 View 2 — Market
- Grid of 6 market cards: EE, FI, LV, LT, SE, NO.
- **Active**: EE only. Selectable; selected card has ink border + paperAlt background. Pre-selected by default since it's the only option.
- **Disabled**: FI, LV, LT, SE, NO. Render with opacity 0.45, cursor not-allowed, "soon" badge top-right. Not selectable.
- Each card shows: 2-letter ISO code (mono), country name (serif 38), registry hostname, total active company count from last sync, all in the layout from `priv/design_prototype/project/views-0-2.jsx`.
- Footer: small mono status `<count> active companies in rik.ee · last sync HH:MM EET`.

### 5.4 View 3 — Filters
- Filter form (live, debounced):
  - **Industry** (multi-select tree, EMTAK)
  - **Region** (multi-select)
  - **Founded year** (range)
  - **Revenue** (EUR, range)
  - **Employees** (range)
  - **Revenue growth** (multi-select of buckets)
  - **Status**: active only by default; toggle to include in liquidation
- Live counter: "X matching companies"
- Preview table: random sample of **100 rows** (regenerated when filters change). UI never shows more than 100.
- "Confirm" button: always enabled. On click:
  - If matches > 1000 → randomly sample 1000.
  - Insert one `CampaignCompany{status: :pending}` per company.
  - Set `campaign.status = :enriching`, `finalized_at = now`.
  - Enqueue first pipeline jobs (see §6).
  - Redirect to view 4.

### 5.5 View 4 — Companies + enrichment

Header: kicker `05 / Funnel · <campaign name>` + serif title `Enriching <accent>N</accent> companies.` Right-side actions: Filter, Columns, Export buttons.

**Stats strip** — 5 tiles in a row, equal flex, hairline dividers between, 2px outer radius:
- Queued, Working (pulsing accent dot), Enriched, ICP miss, Failed.
- Each tile shows mono uppercase label + percentage right; serif 36 number; 2px progress bar sized as `pct`.

**Pipeline meta strip** (mono 11, ink55):
- Left: `● running · <N> workers · <X>/s` (pulsing accent dot when active)
- Then: `queue: <N>`, `elapsed: HH:MM:SS`, `eta: HH:MM:SS`
- Right: `sort: <field> <↑/↓> · <visible> of <total> visible`

Workers/s computed as a 60-second rolling rate from Oban telemetry. ETA = `queue / rate`. Queue size from `oban_jobs` table for the campaign's queue.

**Table** — columns: checkbox, Company (name + `domain · registry-code` mono sub), Industry, Size, Growth (bar glyph), Enrichment (one of three viz styles, see below), Contact (name + title when done), Status (mono right, dot + label).

**Per-row enrichment viz** — visible row UI shows **6 stages**, mapping from the 9 internal Oban jobs in §6:

| Stage | Label | Mapped from internal jobs |
|---|---|---|
| `web` | Website | §6.1 CheckWebsite, §6.2 GoogleSearch |
| `scrape` | Pages | §6.3 FetchLanding, §6.4 ExtractNavigation |
| `parse` | Parse | HTML→markdown step + §6.5 SummarizeCompany |
| `icp` | ICP fit | §6.6 MatchICP |
| `contact` | Contacts | §6.7 PickContactPages, §6.8 ScrapeContactPage |
| `verify` | Verified | §6.9 ExtractContacts validation |

Each stage is in one state: `idle | work | done | skip | fall | fail`. Visualised as **pills** — labelled chips with status dot and hairline tick separators. (The prototype shows two alternates — bar and log — but v1 ships pills only; no per-user toggle.)

**Real-time updates**: `Phoenix.PubSub` topic `"campaign:#{id}"`. Pipeline jobs broadcast `{:stage, company_id, stage, state}` (using the 6 stage names above) and `{:row, company_id, %{...row patch}}` for status/contact field changes.

**Row expansion**: clicking a row expands it inline. Two columns: timestamped pipeline log (mono, format `HH:MM:SS  ✓  message`) on the left; extracted contact card (serif name, mono email + source URL with `verified` accent label, 12/1.5 ai_summary quote) on the right.

**Export modal** — primary action; opens an overlay (rgba(20,18,14,0.45) + 2px blur). 2×3 grid of format cards:
- **CSV** — enabled. Default selected. Footer button: Download CSV.
- **JSON, HubSpot, Pipedrive, Apollo, Webhook** — render the cards but disable them with a "soon" badge. Hooks for v2.

CSV preview block in the modal shows the first 2 rows in mono on paperAlt bg.

Enabled once ≥1 company is `:enriched` with at least one validated, title-matching contact.

**Read-only**: no edits to filters or ICP after this view. No clone in v1.

## 6. Enrichment pipeline

One Oban job per step. Jobs broadcast progress on completion. All jobs are idempotent — if rerun on a company that's already past that step, they no-op.

Queues:
- `registry` — concurrency 1
- `scrape` — concurrency 10, per-domain serialization (one job at a time per host)
- `ai` — concurrency 1
- `export` — concurrency 1

Per-domain serialization: implemented via a Postgres advisory lock keyed on `hashtext(host)` taken at job entry. If lock unavailable, job snoozes 1s. Avoids needing Oban Pro.

Retries: scrape 3× exponential, ai 2×, registry 0.

### 6.1 CheckWebsite
- HEAD then GET fallback on `company.website_url` from registry.
- Alive: 200, 301, 302, 303 with reachable redirect target.
- Dead/missing → enqueue `GoogleSearch`. Alive → enqueue `FetchLanding`.

### 6.2 GoogleSearch
- Google Custom Search API. Query: `"#{company.name}" #{company.region}`.
- Top 5 results → GLM 4.7 picks best given (name, region, industry).
- If model returns "none" or no results → `CampaignCompany{status: :no_website}`, abort downstream.
- Else: save `website_url`, `website_source: :google`, enqueue `FetchLanding`.

### 6.3 FetchLanding (and ScrapeContactPage — shared logic)
1. Try **Req + Floki** (static).
2. **Wallaby trigger** if any of:
   - Response body < 5 KB
   - `<body>` text content < 200 chars
   - SPA shell: presence of `#root`, `#app`, `#__next`, `[data-reactroot]`, `[ng-app]`, or single root `<div>` with no children
   - `<noscript>` block contains "JavaScript" / "enable"
   - Anchor count < 5
3. Wallaby fetch with 10s page timeout, then read rendered HTML.
4. Extract:
   - `generic_email` — regex on landing only: `(info|contact|hello|sales|hi|kontakt|myynti)@<host-or-subdomain>` → save to `company.generic_email` (first match wins)
   - HTML → markdown via `Html2Markdown` (or Floki + custom). Strip nav/footer noise.
   - Save/update `Page{path, markdown, fetched_at, fetcher}`.
5. After landing: enqueue `ExtractNavigation` and `SummarizeCompany`.

### 6.4 ExtractNavigation
- Floki: collect `<nav> a`, `<header> a`, `<footer> a`.
- Filter to same-registrable-domain. Normalize to path. Dedupe.
- Insert `Page{path, in_navigation: true, markdown: nil}` for each.
- Enqueue `PickContactPages` (waits via dependency on `MatchICP`'s success — implemented as a `chain` or by `PickContactPages` checking `campaign_company.status`).

### 6.5 SummarizeCompany
- GLM 4.7: landing markdown → 1-paragraph "what this company does".
- Save to `company.ai_summary`.
- Enqueue `MatchICP`.

### 6.6 MatchICP
- Claude 4.5 Sonnet: `(icp_description, company.ai_summary) → {match: bool, reason: string}`.
- No match: `campaign_company.status = :rejected`, `rejection_reason = reason`. Abort downstream for this campaign.
- Match: enqueue `PickContactPages` (or unblock if already enqueued).

### 6.7 PickContactPages
- Heuristic prefilter on paths: contains any of `contact, team, about, people, staff, kontakt, meeskond, yhteystiedot, henkilosto, tietoa`.
- GLM 4.7: given remaining nav paths → return up to 3 most likely contact-bearing.
- For each selected path: enqueue `ScrapeContactPage`.

### 6.8 ScrapeContactPage
- Same logic as FetchLanding (§6.3) without the generic-email regex.
- When all selected pages for a company are scraped, enqueue `ExtractContacts`.

### 6.9 ExtractContacts
- Claude 4.5 Sonnet: `(target_job_title, concatenated_contact_page_markdown) → [{name, title, email, phone}]`. Returns ALL named people found, not just title-matchers.
- For each candidate:
  - `validated_in_markdown` = email substring exists in any of the company's stored markdown (case-insensitive). Discard if false.
  - `matches_target_title` = title-string check via GLM 4.7 in batched call: `(target_title, [extracted_titles]) → [bool]`. Cheaper than per-row.
- Insert `Person` rows for validated candidates.
- `campaign_company.status = :enriched`.

## 7. Cache & freshness

- Re-enrich a company if `last_enriched_at` is null OR older than **30 days** OR `website_url` changed since last run.
- Pages: don't re-fetch within 30 days unless website_url changed.
- AI summary: cached on Company (re-used across campaigns).
- ICP-match: re-run per campaign (different ICP per campaign).
- Contacts extraction: cached extracted Person rows are reused; only `matches_target_title` is recomputed per campaign (different target title).

## 8. Configuration

All third-party credentials live in app config (`runtime.exs`), read from env. There is **no settings page** and no per-user customisation in v1 — accent, density, and funnel viz are global constants. Required env:

- `OPENROUTER_API_KEY`
- `GOOGLE_CSE_API_KEY`
- `GOOGLE_CSE_ENGINE_ID`

In prod, missing keys raise on boot via `System.fetch_env!/1`. In dev, missing keys cause enrichment jobs to fail loudly — no UI banner.

## 9. Export

CSV-only. Button on view 4 triggers download of `colt-#{campaign.name}.csv`. Instantly's standard import columns:

```
email, first_name, last_name, company_name, website, title, snippet
```

- One row per Person where:
  - `campaign_company.status == :enriched`
  - `person.validated_in_markdown == true`
  - `person.matches_target_title == true`
  - `campaign_company.included_in_export == true`
- `snippet` = `company.ai_summary` (truncated 240 chars). Useful for Instantly personalization variables.
- v2: optional checkbox to include `generic_email` rows where no named contact exists.

## 10. Lifecycle

```
Campaign:        draft → collecting → enriching → complete (auto when all CC terminal) → archived
CampaignCompany: pending → scraping → (rejected | no_website | enriched | failed)
```

## 11. Non-goals (v1)

- **Estonia only.** Finland (PRH Avoindata + Tilinpäätöstiedot), Latvia, Lithuania, Sweden, and Norway are deferred. Data model and UI carry their slots but they're disabled.
- No campaign clone / edit / re-run.
- No team accounts.
- No CRM integrations beyond CSV.
- No paid registry data sources (teatmik.ee scraping deferred).
- No phone-number validation.
- No outreach features (sending is Instantly's job).

## 12. Open risks

- **rik.ee XBRL parsing**: needs spike before scoping registry ingest. If revenue isn't extractable, growth filters can't ship in v1.
- **Per-domain Oban serialization** via advisory locks: needs load testing — under heavy contention, snooze loops could starve other domains.
- **Wallaby detection heuristics**: false positives waste time, false negatives miss SPA contacts. Tunable thresholds in §6.3 should be config-driven so we can iterate without redeploys.
- **Hallucinated emails normalized**: substring check misses `name [at] company [dot] com` style obfuscation. Document choice to ignore obfuscated emails in v1.
- **Google CSE cost**: $5 per 1000 queries; only triggers on dead-website fallback. Worst case 1000 companies = $5/campaign. Acceptable.
- **GDPR**: storing scraped personal contact info from EU sites is a real concern. v1 ships under "legitimate interest for B2B prospecting"; revisit before public launch.
