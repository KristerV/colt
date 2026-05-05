# Phased build plan

Build order for the spec in `docs/spec.md`, sliced so each phase ships something independently testable. **Clear context between phases.** Each phase should be picked up by a fresh agent with only these three docs and the current code state.

## How to use this doc

- Work top-to-bottom, one phase at a time. Don't start the next phase until the current phase's **Acceptance** checks pass.
- The phase intro is the only thing that changes phase-to-phase. Spec (`docs/spec.md`) and design (`docs/design.md`) are canonical and don't change unless we're deliberately revising them.
- Each phase calls out **Deferred** items — things you'll see referenced in the spec but should *not* build yet. Resist the urge to do them now; they belong to a later phase that has the right context.
- After each phase: commit, run the Acceptance bullets manually, then start a new conversation for the next phase.

## Working with third-party services

Before writing code that calls any external API, follow this procedure. Applies across phases — most directly to Phase 1 (rik.ee) and Phase 4a (OpenRouter, Google CSE).

1. **Read the official docs first.** Use WebFetch / WebSearch to load the current docs. Don't write the integration from memory — endpoints, auth schemes, and rate limits drift.
2. **Capture the load-bearing facts** in `docs/spec.md` (or in a comment at the top of the client module if too granular for the spec): base URL, auth scheme, rate limits, the specific endpoints we use, response shape we depend on. Future-you re-reading the module shouldn't have to re-fetch the docs.
3. **Check for an existing contract.** Some services have credentials, terms, or rate-limit tiers already negotiated with the user. Ask before generating new keys or assuming defaults. See spec §3.2 for known contracts.
4. **Build a thin client first.** Single module under `Colt.<Service>`, callable from `iex` (or `mix run -e`), returning `{:ok, _} | {:error, _}`. Don't inline the HTTP calls into the consumer (Oban job, LiveView, etc.).
5. **Probe with the dev helper before wiring.** Add an entry in `priv/dev_helpers.exs` (created in Phase 4a) for each external service so a future agent can sanity-check connectivity in one line.

## Phase order at a glance

```
0.  Foundation          — design system + settings on the auth boilerplate
1.  Registry ingest     — rik.ee → Estonian companies + financials in DB
2.  Campaign setup      — views 0–2 (name, ICP, market)
3.  Filters + preview   — view 3 (live counter, preview, sample-to-1000)
4a. Enrichment infra    — OpenRouter, Google CSE, Scrape (Req+Wallaby), markdown, locks
4b. Enrichment jobs     — 9 Oban jobs assembled on top of 4a, end-to-end
5.  Funnel (view 4)     — stats strip, table, 3 viz styles, expanded row
6.  Export modal        — CSV download
```

Phases 0, 1 are independent. Phase 2 depends on 0. Phase 3 depends on 1 + 2. Phase 4a depends on 0 (env-config wiring for API keys). Phase 4b depends on 3 + 4a. Phase 5 depends on 4b. Phase 6 depends on 5.

---

## Phase 0 — Foundation (design system + branded shell)

**Already done in the boilerplate** (don't rebuild): magic-link auth via Ash Authentication, `Colt.Accounts.User`, token resource, magic-link sender, `ColtWeb.AuthController`, `ColtWeb.LiveUserAuth`, router with `ash_authentication_live_session`, `ColtWeb.Layouts` + `core_components.ex`, Oban + Oban.Web mounted.

**Goal**: a logged-in user lands on a Liid-branded shell with the design system in place. Auth flows already work; we wrap them — including the sign-in / magic-link screens — in the Liid look. **No user settings, no per-user customisation.** All third-party credentials are global (env / `runtime.exs`).

**Build**:
- Brand the existing layouts: replace the default Phoenix shell in `ColtWeb.Layouts.app` with the Liid top bar (wordmark + stepper placeholder + campaign chip slot + avatar). Wordmark text = "Liid". Move whatever the boilerplate puts on `/` to a placeholder home that lists the user's campaigns (empty for now).
- **Auth screens** (sign-in, register, magic-link request, confirmation): currently use AshAuthentication's DaisyUI overrides. Replace with Liid styling so the login flow doesn't look like raw DaisyUI. Either ship our own `AshAuthentication.Phoenix.Overrides` module or skip the built-in `sign_in_route` and render our own LiveView. Either way, every screen the user can reach must match the design system.
- Global CSS in `assets/css/app.css`: oklch tokens (per design §1), `--accent` custom property (single global value: forest `#3d7a3d`), three font families (Inter Tight, Instrument Serif, JetBrains Mono via Google Fonts `<link>`), and the four keyframes (`liid-pulse, liid-blink, liid-shimmer, liid-tick`).
- Tailwind theme: extend with token names so utility classes resolve to oklch values. Don't substitute `gray-*`. (Project uses Tailwind v4 — extend via `@theme` in `app.css`, not a `tailwind.config.js`.)
- Reusable function components in `ColtWeb.Components.Liid` (one module, multiple functions): `screen/1`, `top_bar/1`, `btn/1`, `headline/1`, `status_dot/1`, `icon/1` (with the icon path map copied verbatim from `priv/design_prototype/project/liid-shared.jsx`).
- App config for third-party keys (used in later phases, but wire the read sites now): `OPENROUTER_API_KEY`, `GOOGLE_CSE_API_KEY`, `GOOGLE_CSE_ENGINE_ID` in `config/runtime.exs`. Prod uses `System.fetch_env!/1`; dev tolerates missing.

**Acceptance**:
- `mix phx.server` boots; `/` shows the Liid wordmark and Liid-branded shell.
- Magic-link sign-in flow walked end-to-end uses the Liid design (no DaisyUI button shapes, no Phoenix default layout).
- All three fonts render. Inspect element: paper/ink colors are oklch, not hex grays.
- `--accent` cascades from the body root; status dots / buttons read from it.

**Deferred**: anything from views 0–4. No campaign resources, no settings page (there is none in v1), no Tweaks panel.

**Likely files**:
- `lib/colt_web/components/liid.ex` (new)
- `lib/colt_web/components/layouts.ex` + `layouts/app.html.heex`, `root.html.heex` (modify)
- `lib/colt_web/auth_overrides.ex` (modify — Liid styling)
- `lib/colt_web/live/home_live.ex` (modify — rebrand)
- `assets/css/app.css` (modify)
- `config/runtime.exs` (add OpenRouter / Google CSE env reads)
- Router: keep as-is (no `/settings`).

---

## Phase 1 — Registry ingest

**Goal**: nightly cron populates `companies` + `annual_reports` from rik.ee Avaandmed (Estonia). Growth buckets computed. **Estonia only — Finland and other markets are deferred (spec §11).**

**Build**:
- `Company` resource (no per-user scoping). Identity `[:registry_code, :market]`. Fields per spec §4. Keep the `market` column even though only `:ee` is populated — adding new markets later stays additive.
- `AnnualReport` resource. Identity `[:company_id, :year]`. Fields per spec §3.1, `source: :rik`.
- One ingest worker: `Colt.Ingest.RikEE`. Service convention: `run/0` with `with` chain, `{:ok, summary}` return.
- The worker downloads the open-data dump, streams the parse (don't load full file), upserts companies, then upserts the last 3 fiscal years of annual reports.
- Action `Company.compute_growth/1` (called per company after upsert) sets `revenue_latest`, `employees_latest`, `revenue_growth_bucket` per spec §3.1.
- Oban cron entry: daily 03:00 UTC, queue `registry`, runs `Colt.Ingest.RikEE`.
- Mix task `mix colt.ingest` runs the worker on demand. (No `--market` flag yet — only one market.)

**Acceptance**:
- `mix colt.ingest` completes end-to-end on a fresh DB.
- `docker exec -ti postgres psql -U postgres -d colt_dev -c "select count(*) from companies where market = 'ee'"` returns > 100,000.
- 5 randomly chosen rows have `revenue_growth_bucket` ∈ `{:declining, :stagnant, :slow, :growing_2x, :growing_10x}` or `nil`.
- Companies with <2 annual reports have `nil` growth bucket.
- Re-running the ingest is idempotent (counts don't double).

**Deferred**: any UI exposing this data. Finland / Latvia / Lithuania / Sweden / Norway ingests. The pre-spike risk in spec §3.1 (XBRL parsing) lives here — if rik.ee XBRL turns out impenetrable, surface it before moving on.

**Likely files**:
- `lib/colt/companies/company.ex`, `annual_report.ex`
- `lib/colt/ingest/rik_ee.ex`, `ingest.ex` (parent module)
- `lib/mix/tasks/colt.ingest.ex`
- `config/config.exs` (Oban cron)

---

## Phase 2 — Campaign setup (views 0–2)

**Goal**: a user can create a campaign, describe ICP + target title, and pick a market. No filtering, no enrichment yet.

**Build**:
- `Campaign` resource per spec §4. Lifecycle: `:draft` after creation, `:collecting` after market is set.
- `CampaignCompany` resource scaffolded (not used yet).
- LiveViews:
  - View 0 (`/campaigns/new`) — campaign name input + Recent sidebar (last 4 campaigns of the user with done/total + relative time).
  - View 1 (`/campaigns/:id/icp`) — `icp_description` textarea (max 2000) + single `target_job_title` input.
  - View 2 (`/campaigns/:id/market`) — 6 market cards. **EE only is active and pre-selected.** FI / LV / LT / SE / NO disabled with "soon" badge. Footer shows live count from `Company` table for EE + last sync time from latest `AnnualReport.updated_at` aggregate (or a dedicated `IngestRun` row — pick one, document it).
- Forward-only stepper: clicking past steps allowed (read), clicking future steps disabled until current step has data.
- All three views match `priv/design_prototype/project/views-0-2.jsx` per `docs/design.md` §3.

**Acceptance**:
- Walk: `/campaigns/new` → enter "Test EE SaaS" → continue → paste ICP + title → continue → pick Estonia → continue.
- DB has `Campaign{name: "Test EE SaaS", status: :collecting, market: :ee, icp_description: "...", target_job_title: "CTO"}`.
- Disabled markets cannot be clicked.
- Recent sidebar on `/campaigns/new` shows the just-created campaign with `0 / 0` ratio after refresh.
- Browser visual: matches the prototype within ~5% spacing tolerance. Type families correct. Accent token applied.

**Deferred**: filters, enrichment trigger, view 3+, view 4+.

**Likely files**:
- `lib/colt/campaigns/campaign.ex`, `campaign_company.ex`
- `lib/colt_web/live/campaigns/new_live.ex`, `icp_live.ex`, `market_live.ex`
- Tests covering the create + advance flow.

---

## Phase 3 — Filters + preview (view 3)

**Goal**: user picks filters, sees live company count and a 100-row preview, hits Confirm to enqueue enrichment (which is a no-op stub at this phase — Phase 4 wires the real pipeline).

**Build**:
- View 3 (`/campaigns/:id/filters`) per spec §5.4 + design §3.
- Filter form fields: industry (multi-chip), employees range, trajectory (5 buckets), region, founded year range, signals (has registered website, VAT registered, filed annual report 2024). Live (debounced 200ms) recompute on every change.
- A `Colt.Companies.list_filtered/2` action on `Company` taking the filter struct + market, returning `{count, preview_100_random}`. Use a single SQL pass with `count(*) over ()` for efficiency.
- Counter card with serif 76px number + capacity bar.
- Active-chips row (summary chips with X to remove).
- Preview list: 4-column grid bound to the random sample. Loading shimmer when filters change.
- "Run enrichment on N" button — on click:
  - If `count > 1000`, randomly sample 1000 in SQL (`order by random() limit 1000`).
  - Insert `CampaignCompany{status: :pending}` rows in a single transaction.
  - Set `campaign.status = :enriching`, `finalized_at = now`.
  - **Stub**: enqueue a `Colt.Enrichment.Stub` Oban job that just logs and marks the campaign company `:enriched` after 2s. Real pipeline in Phase 4.
  - Redirect to view 4 (which is a placeholder until Phase 5 — show "Enrichment running, view 4 not built yet").

**Acceptance**:
- Adjust any filter → counter updates within ~500ms.
- Counter caps display at 1000 in the bar but shows real count above.
- Preview list updates in lockstep.
- Click "Run enrichment on N" → campaign moves to `:enriching`, N (≤1000) `CampaignCompany` rows exist, a Stub job runs and resolves them.
- Random sample doesn't repeat between two consecutive Confirms (within reason).
- Cost-estimator line from prototype is **not** rendered (per design §5).

**Deferred**: the actual enrichment pipeline.

**Likely files**:
- `lib/colt_web/live/campaigns/filters_live.ex`
- Action additions to `Colt.Companies.Company` (`:list_filtered`, `:sample_for_campaign`)
- `lib/colt/enrichment/stub.ex` (Oban worker, throwaway)

---

## Phase 4a — Enrichment infrastructure

**Goal**: every shared primitive the pipeline needs, callable in isolation from `iex`. **No Oban jobs, no campaign concept** — just clean modules with `run/1`-style entry points and `{:ok, _} | {:error, _}` returns.

Why split this from 4b: each piece below carries a real risk (API auth, lib choice, error semantics, prompt-caching shape, browser automation on your actual machine). Better to validate them once, in isolation, than to debug them while also debugging job orchestration.

**Build**:
- `Colt.AI` — OpenRouter client.
  - `complete(model, prompt_or_messages, opts)` where `model ∈ {:cheap, :smart}`. `:cheap` → GLM 4.7, `:smart` → Claude 4.5 Sonnet via OpenRouter.
  - Supports `system:` (cached across calls when the underlying provider supports prompt caching), `response_format: :json` with a schema, `max_tokens`, `temperature`.
  - Reads API key from app config (`Application.fetch_env!(:colt, :openrouter)[:api_key]`), sourced from `OPENROUTER_API_KEY`.
  - Single retry with backoff on transient errors (5xx, timeouts).
- `Colt.Search` — Google Custom Search client.
  - `google(query, opts)` returns up to 10 `%Result{title, url, snippet}` results.
  - Reads CSE key + engine ID from app config (`GOOGLE_CSE_API_KEY`, `GOOGLE_CSE_ENGINE_ID`).
- `Colt.Scrape` — fetcher with static-first / Wallaby-fallback strategy.
  - `fetch(url)` returns `{:ok, %{html, fetcher: :static | :wallaby, status, final_url}} | {:error, reason}`.
  - Static path: Req with sensible UA + redirect handling.
  - Fallback heuristics per spec §6.3 (body < 5KB, SPA shell `#root | #app | #__next | [data-reactroot] | [ng-app]`, `<noscript>` JS markers, anchor count < 5).
  - Wallaby path: 10s timeout, return rendered HTML.
  - Polite default: short jitter delay before each request (configurable).
- `Colt.Markdown` — HTML → markdown converter.
  - `from_html(html, opts)` returns clean markdown. Strip nav / footer / script / style. Either wrap a lib or roll a Floki pipeline — pick what gives readable output and document the choice.
- `Colt.Locks` — advisory-lock helper.
  - `with_domain_lock(host, fun)` does `pg_try_advisory_xact_lock(hashtext(host))`; if unavailable, returns `:locked` so callers can snooze.
  - Thin wrapper, but having it as a module makes the call sites readable.
- `Colt.Enrichment.Broadcast` — PubSub helper for jobs.
  - `stage(campaign_company_id, stage, state)` and `row(campaign_company_id, patch)` → publish to topic `"campaign:#{campaign_id}"`. No subscriber yet (Phase 5 wires the funnel).
- Resources finalised here: `Colt.Companies.Page`, `Colt.Companies.Person`. `Page` identity on `[:company_id, :path]`.

**Acceptance** — all from `iex -S mix` (or `mix run -e` per project convention):
- `Colt.AI.complete(:cheap, "Say hi") == {:ok, "..."}` round-trips against OpenRouter (key from env).
- `Colt.AI.complete(:smart, messages, response_format: :json, schema: %{...})` returns parsed JSON conforming to the schema.
- `Colt.Search.google("bolt.eu")` returns a list of results with URLs.
- `Colt.Scrape.fetch("https://example.com")` returns `:static` fetcher.
- `Colt.Scrape.fetch("<some SPA URL you know>")` returns `:wallaby` fetcher and includes rendered content not present in the raw HTML.
- `Colt.Markdown.from_html(html)` on a real landing page produces markdown ≤ 30% the byte size of the input with no obvious garbage.
- `Colt.Locks.with_domain_lock("example.com", fn -> ... end)` can be observed to serialize: kick off 3 concurrent calls in iex on the same host, verify they don't overlap.
- `Colt.Enrichment.Broadcast.stage(...)` publishes a message a manual `Phoenix.PubSub.subscribe/2` receives.
- `Page` and `Person` resources have migrations applied; they read/write via Ash actions.
- A `dev_helpers.exs` script exists with one-liners for running each of the above by hand. Useful to keep around forever.

**Deferred**: any Oban worker, the actual 9 jobs, anything campaign-aware.

**Likely files**:
- `lib/colt/ai.ex`, `lib/colt/ai/open_router.ex`
- `lib/colt/search.ex`
- `lib/colt/scrape.ex`, `lib/colt/scrape/{static,wallaby,detect}.ex`
- `lib/colt/markdown.ex`
- `lib/colt/locks.ex`
- `lib/colt/enrichment/broadcast.ex`
- `lib/colt/companies/{page,person}.ex`
- `priv/repo/migrations/*_persons_pages.exs`
- `priv/dev_helpers.exs`

---

## Phase 4b — Enrichment jobs

**Goal**: triggering enrichment on a campaign actually runs the 9-job pipeline end-to-end and produces enriched companies + persons. Each job is a thin orchestrator over Phase-4a primitives. **No funnel UI yet** — verify via DB queries and logs.

**Build**:
- Replace the Phase-3 stub with the real per-step Oban jobs per spec §6:
  - 6.1 `CheckWebsite` (uses `Colt.Scrape` for HEAD/GET, no markdown)
  - 6.2 `GoogleSearch` (uses `Colt.Search` + `Colt.AI :cheap` to pick best result)
  - 6.3 `FetchLanding` (uses `Colt.Scrape` + `Colt.Markdown`; runs the generic-email regex on the raw HTML)
  - 6.4 `ExtractNavigation` (Floki on landing HTML — no new infra)
  - 6.5 `SummarizeCompany` (`Colt.AI :cheap`)
  - 6.6 `MatchICP` (`Colt.AI :smart`, sets rejection reason on miss)
  - 6.7 `PickContactPages` (`Colt.AI :cheap` over filtered nav paths)
  - 6.8 `ScrapeContactPage` (`Colt.Scrape` + `Colt.Markdown`, no regex)
  - 6.9 `ExtractContacts` (`Colt.AI :smart` for extraction, then a batched `:cheap` call for `matches_target_title`, then substring validation)
- All jobs idempotent — they no-op on already-completed steps. Pattern: read `CampaignCompany`, check stage state, return `:ok` early if past.
- Each job ends with `Broadcast.stage/3` and either an `Oban.insert` for the next step or a terminal status update.
- Queues per spec §6 intro: `registry`, `scrape` (10 workers, calls `Locks.with_domain_lock` and `Oban.snooze` if `:locked`), `ai` (1 worker), `export` (1 worker).
- Config gate: on boot (or on first enqueue), assert env-sourced API keys are present. Missing in prod → raise; missing in dev → log and allow enqueue (jobs will fail loudly).
- Stage-to-job mapping (broadcast stage atoms must match spec §5.5 / design):
  - `web` ← CheckWebsite, GoogleSearch
  - `scrape` ← FetchLanding, ExtractNavigation
  - `parse` ← FetchLanding's markdown step + SummarizeCompany
  - `icp` ← MatchICP
  - `contact` ← PickContactPages, ScrapeContactPage
  - `verify` ← ExtractContacts validation step

**Acceptance**:
- Set up a campaign with 5–10 EE companies (narrow filters) and confirm.
- After ~5 minutes:
  - ≥1 `CampaignCompany.status = :enriched` with associated `Person` rows.
  - ≥1 `:rejected` with an ICP rejection reason populated.
  - ≥1 `:no_website` if any seed lacks a website.
  - All persisted `Person` rows have `validated_in_markdown = true`.
  - Re-running enrichment on a finished campaign no-ops.
- `oban_jobs` shows jobs distributed across the four queues.
- Per-domain lock observable: contrive 5 `FetchLanding` jobs for the same host, verify only one runs at a time.
- Total OpenRouter spend < $5 on this run (sanity-check prompt caching is working).
- A subscriber to the campaign's PubSub topic (manual `Phoenix.PubSub.subscribe/2` in iex) receives a stream of `{:stage, ...}` and `{:row, ...}` messages.

**Deferred**: funnel UI (the broadcast events have no consumer yet — Phase 5 wires it).

**Likely files**:
- `lib/colt/enrichment/{check_website,google_search,fetch_landing,extract_navigation,summarize_company,match_icp,pick_contact_pages,scrape_contact_page,extract_contacts}.ex`
- `lib/colt/enrichment.ex` (parent / dispatch)
- `config/config.exs` (Oban queue config)

---

## Phase 5 — Funnel view (view 4)

**Goal**: real-time progress UI for the enrichment running underneath. Three viz styles, expanded row, all the meta.

**Build**:
- View 4 (`/campaigns/:id/funnel`) per spec §5.5 + design §3.
- `Phoenix.PubSub` topic `"campaign:#{id}"`. Each enrichment job broadcasts:
  - `{:stage, company_id, stage, state}` using the 6 visible stage names (`web | scrape | parse | icp | contact | verify`) per the mapping in spec §5.5.
  - `{:row, company_id, %{...patch}}` for status, contact name/title, error.
- Stats strip computed from `CampaignCompany` aggregates (5 buckets). Refresh on broadcast.
- Pipeline meta strip: `running · N workers · X/s · queue: N · elapsed · eta`. Workers/s = 60-sec rolling rate from Oban telemetry. ETA = `queue / rate`.
- Pills viz only. (Bar and Log alternates from the prototype are not built; no toggle.)
- Row expansion: click row → inline two-column expand. Pipeline log on the left (timestamped from job records), contact card on the right.
- Mark Export button as enabled when ≥1 enriched company has a validated, title-matching Person. The button does nothing yet (Phase 6 wires the modal).

**Acceptance**:
- Run a Phase-4 enrichment on a small campaign, watch view 4 update live.
- Stats strip totals match DB counts at any point in time.
- Pills viz renders without breaking row width.
- Expanded row shows real timestamps from the job log.
- Pipeline meta numbers update at least every 5s.

**Deferred**: Export modal contents.

**Likely files**:
- `lib/colt_web/live/campaigns/funnel_live.ex`
- `lib/colt_web/components/funnel.ex` (StatsStrip, FunnelRow, EnrichmentViz dispatch)
- `lib/colt/enrichment/broadcast.ex` (helper used by all jobs)
- `lib/colt/oban_stats.ex` (workers/s, queue size, ETA)

---

## Phase 6 — Export

**Goal**: user exports an Instantly-format CSV from the funnel page.

**Build**:
- Export modal per spec §9 + design §3 (View 4 → Export modal).
- 6 format cards in 2×3 grid. **CSV enabled, others disabled with "soon" badge.**
- CSV preview block in the modal renders the first 2 rows of the actual data (not mock data).
- Download flow: `ColtWeb.Export.csv_for_campaign/1` → streams a CSV with columns `email, first_name, last_name, company_name, website, title, snippet`. One row per Person where:
  - `campaign_company.status == :enriched`
  - `person.validated_in_markdown == true`
  - `person.matches_target_title == true`
  - `campaign_company.included_in_export == true`
- `snippet` = first 240 chars of `company.ai_summary`.
- Filename: `liid-#{slugified-campaign-name}.csv`.

**Acceptance**:
- Click Export on a finished campaign → modal opens.
- Click Download CSV → file downloads.
- Open the CSV in Instantly → import succeeds, named contacts present.
- Spot-check: every email in the CSV exists somewhere in that company's stored page markdown (validates the validation).

**Deferred**: JSON / HubSpot / Pipedrive / Apollo / Webhook integrations. They're cards in the modal but disabled. Add in v2.

**Likely files**:
- `lib/colt_web/components/export_modal.ex`
- `lib/colt_web/controllers/export_controller.ex` (or LiveView download)
- `lib/colt/export/csv.ex`

---

## After phase 6

You have a working end-to-end Liid. Now revisit:
- Settings page UX polish.
- Empty/error states across all views.
- Performance on a campaign with the full 1000-company funnel running.
- The two open risks from spec §12: rik.ee XBRL parsing depth (validated in Phase 1 — but tested under load now), Wallaby false-positive rate (tunable thresholds).
