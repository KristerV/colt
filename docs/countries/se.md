# Sweden — Bolagsverket + SCB

Plan for ingesting Swedish companies (basic registry data + revenue +
employees) under `Colt.Services.Ingest.Se.Bolagsverket.*`. All sources
below are free of charge; the API needs OAuth2 client credentials that
Bolagsverket issues on request via a one-time customer form (no
agreement, no fee).

## Sources

### 1. Bolagsverket "Värdefulla datamängder" (HVD) API — **free, OAuth2**

Launched 2025-02-03 by Bolagsverket together with SCB to satisfy the
EU Open Data Directive HVD list. Free of charge, no agreement required,
but a per-client `client_id` / `client_secret` must be requested via the
customer form at:

- https://bolagsverket.se/apierochoppnadata/hamtaforetagsinformation/vardefulladatamangder/kundanmalantillapiforvardefulladatamangder.5528.html

Endpoints (REST, JSON):

| Function       | Method | URL                                                                          |
|----------------|--------|------------------------------------------------------------------------------|
| Token          | POST   | `https://portal.api.bolagsverket.se/oauth2/token`                            |
| Health         | GET    | `https://gw.api.bolagsverket.se/vardefulla-datamangder/v1/isalive`           |
| Organisation   | POST   | `https://gw.api.bolagsverket.se/vardefulla-datamangder/v1/organisationer`    |
| Document list  | POST   | `https://gw.api.bolagsverket.se/vardefulla-datamangder/v1/dokumentlista`     |
| Document fetch | GET    | `https://gw.api.bolagsverket.se/vardefulla-datamangder/v1/dokument/{id}`     |

OAuth scopes: `vardefulla-datamangder:read vardefulla-datamangder:ping`
(client credentials grant).

Rate limit: **60 requests per minute per client** (per Bolagsverket FAQ).

Returns the SBT TO ("sammansatt bastjänst — grunddata om organisationer")
model. From SCB you also get the **size class** (employee band) and
SNI code; from Bolagsverket you get names, addresses, registration
status, legal form. **Exact revenue and exact employee counts are NOT
in `organisationer`** — they only appear in the iXBRL annual-report
document fetched via `dokument/{id}`.

### 2. Bulk downloadable files — **free, no auth**

Listed at
https://bolagsverket.se/apierochoppnadata/hamtaforetagsinformation/nedladdningsbarafiler.2517.html
(CAPTCHA-gated landing page; the actual file URLs are revealed after
the human verification step). Two ZIP files refreshed weekly:

- `bolagsverket_bulkfil.zip` — all organisations registered with
  Bolagsverket. Unpacks to .txt (delimited).
- `scb_bulkfil.zip` — all organisations from SCB's företagsregister,
  including the **banded employee count** and SNI codes.

Direct URLs aren't published in machine-readable form, so the planned
implementation goes through the OAuth API first (paginated
`organisationer` calls). If the user obtains the direct ZIP URLs
through the customer page, we'll add a `Download` stage that prefers
the ZIP to avoid hammering the 60-req/min limit on a one-shot seed.

### 3. SCB Företagsregistret API — **free, certificate auth**

Separate from HVD. Same underlying data; finer-grained search but
requires a certificate-based agreement and is currently superseded by
HVD for our needs. Not used in this pipeline.

- https://www.scb.se/vara-tjanster/bestall-data-och-statistik/foretagsregistret/foretagsregistrets-tjanster/foretagsregistrets-webbtjanster/

## iXBRL annual report — taxonomy fields

Sweden's annual-report taxonomy is the `se-*` family published at
https://www.taxonomier.se. Element names are descriptive (unlike PRH's
`fi_met:mi53` opaque codes), which simplifies extraction.

Required fields, all denominated in **SEK**:

| Concept             | iXBRL element                            | Notes                                       |
|---------------------|------------------------------------------|---------------------------------------------|
| Net turnover        | `se-gen-base:Nettoomsattning`            | Period fact; pick the current period        |
| Average employees   | `se-gen-base:MedelantaletAnstallda`      | Optional for small companies                |

Currency conversion: revenue is stored as `revenue_eur` per schema.
We convert SEK → EUR using a fixed module constant
(`@sek_eur 0.088` ≈ mid-2026 rate); accuracy is not critical for
B2B-prospecting filters that bucket revenue by 10× growth bands.
If FX accuracy ever matters we'll move to a per-FY ECB reference rate.

Period filtering: iXBRL `period/endDate` is the FY end (e.g.
`2024-12-31`). We accept any FY whose `endDate` year is one of the
last `:ingest_max_years` (default 3) and store under that year.

## Coverage — HONEST

**iXBRL digital filing has been available since 2020, mandatory only
from 1 July 2024** (i.e. FY ending on or after that date). For ABs
(aktiebolag, the dominant company form in the registry, ~700k entities)
this means:

- FY2024 onwards: → trending toward 100% over 18 months, today
  realistically **50-70%** as the mandate ramps up.
- FY2023 and earlier: voluntary. Filings exist but **likely <10%
  of active ABs** — biased toward larger companies that already used
  XBRL tooling.

Other company forms (handelsbolag, ekonomiska föreningar, branches)
file annual reports irregularly or not at all; iXBRL coverage is
effectively zero outside AB.

Realistic delivered coverage for revenue + employees:

| Cohort                          | Coverage |
|---------------------------------|----------|
| Active ABs, FY2024 (latest)     | 50-70%   |
| Active ABs, FY2023              | 5-15%    |
| All Swedish active legal entities | <40%   |

Will look much better in 2027-2028 once two full mandatory cycles
have passed. Today we should label the missing 30-50% honestly in the
UI rather than impute.

For `revenue_growth_bucket` specifically, we need **two consecutive
filed years per company**. Today that's a small minority of ABs
because the 2024 mandate only just produced one fiscal cycle in
the iXBRL set. Expect growth-bucket coverage of single-digit % in
the first run; rising fast over the next two years.

## Pipeline stages

Mirrors the EE / FI shape.

```
Colt.Services.Ingest.Se.Bolagsverket            # orchestrator
├── Auth                                         # OAuth2 client-credentials token cache
├── CompaniesImport                              # paginated /organisationer → upsert_full
├── AnnualReports                                # /dokumentlista + /dokument/{id} → iXBRL parse
└── GrowthRollup                                 # shared SQL rollup (same query as EE/FI)
```

We intentionally skip a `Download` stage at first — the OAuth-gated
`organisationer` walk is the seed of record. If the user discovers
the public bulk-ZIP URLs and shares them, swap in a streaming download
+ NDJSON parser then. The interface to the rest of the pipeline
doesn't change.

### iXBRL parsing — reuse from FI?

The FI/PRH parser is regex-based, keyed by `fi_met:md103` facts plus
an MCY dimension context. The SE taxonomy uses **direct element names**
(`se-gen-base:Nettoomsattning`) with no dimension — structurally
different. A trivial cousin parser (~80 LOC) lives in
`Se.Bolagsverket.AnnualReports`. Extracting a `Colt.Services.Ingest.Xbrl`
helper would force both files through a generic-element regex that
neither needs; not worth the abstraction today. Documented as
intentional duplication.

## Per-filing fetch cost

- OAuth token: 1 call, valid ~1h.
- `organisationer`: bulk paginated, ~1 call per 100 orgs.
- `dokumentlista`: 1 call per org → list of available filings.
- `dokument/{id}`: 1 call per filing.

For ~700k ABs with ~50% FY2024 iXBRL coverage = ~350k filings →
~700k API calls at 60/min = **~190 hours steady-state**. Practical
strategy: walk only `:registered` companies, restrict to N most-recent
filings per org via `dokumentlista`, and cache filing IDs so the
weekly cron pulls only new ones.

For Phase D verification (slice of 1000 companies), expect ~20 minutes
including the rate-limit wait.

## Estimated counts (May 2026)

- Total registered organisations in Bolagsverket: ~1.6M
- Active ABs (`registered`): ~700k
- ABs with at least one iXBRL filing: ~300-400k (growing)
- ABs with FY2024 iXBRL: ~250-350k

## For the user

### One-time setup

Apply for OAuth2 client credentials via
https://bolagsverket.se/apierochoppnadata/hamtaforetagsinformation/vardefulladatamangder/kundanmalantillapiforvardefulladatamangder.5528.html
(email + phone; free; no agreement required). Bolagsverket emails
back `client_id` and `client_secret` within a few business days.

Set in `config/runtime.exs` (prod) and `config/dev.secrets.exs` (dev):

```elixir
config :colt, :bolagsverket,
  client_id: System.fetch_env!("BOLAGSVERKET_CLIENT_ID"),
  client_secret: System.fetch_env!("BOLAGSVERKET_CLIENT_SECRET")
```

Per the `feedback_credentials_pattern` rule: prod raises on missing
env, dev falls back to `nil` and the ingest returns `{:error,
:missing_api_key}` instead of crashing.

### Oban cron line (for `config/config.exs`)

Add to the `crontab:` list, between PrhIngest and SendDueEmails:

```elixir
{"0 5 1 * *", Colt.Jobs.BolagsverketIngest},
```

(Monthly on the 1st at 05:00 UTC — 2h after RIK, 1h after PRH. Same
queue `:registry`, concurrency 1, so they serialise.)

### Enum / schema deltas

None required. `:se` is already in `Company.market` and `:bolagsverket`
is already in `AnnualReport.source`. The downstream `GrowthRollup`
SQL is source-agnostic.

### Cache directory

Add to `config/config.exs` alongside `prh_fi_cache_dir`:

```elixir
bolagsverket_se_cache_dir: "priv/ingest_cache_se",
```

(Used today only for the OAuth token JSON; populated with the bulk
ZIPs if the user later shares those URLs.)
