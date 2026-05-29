# Lithuania — Registrų centras + Sodra ingest

## Summary

Lithuania is the **two-source country** flagged in `data-sources.md`:

1. **Registrų centras (RC)** publishes the basic legal-entities register (JAR)
   and every filed annual financial statement (profit/loss + balance sheet)
   as direct CSV downloads from `registrucentras.lt`. **No login, no
   Cloudflare challenge, no API key. CC-BY 4.0.** This handles
   `companies` + `annual_reports.revenue_eur`.
2. **Sodra** publishes per-employer monthly counts of insured persons
   (apdraustieji) and average salary — best free headcount source of any
   country in our list. **CC-BY 4.0**. BUT all Sodra download URLs sit
   behind `atvira.sodra.lt`, which serves a **managed Cloudflare interactive
   challenge** to non-browser clients. Vanilla `Req`, `curl`,
   `curl-impersonate` (`chrome124` TLS), and `cloudscraper` were all rejected
   with HTTP 403 + `cf-mitigated: challenge` during Phase A probing
   (2026-05-28). The data is free and licensed for redistribution, the
   delivery channel is not bot-friendly.

### What this means for the ingest

- **RC pipeline ships immediately.** Identity, status, address, revenue
  per filed fiscal year — all working with the same shape as EE/RIK.
- **Sodra pipeline is wired up but the downloader is pluggable.** The
  default `Req` fetch will 403; a `:sodra_fetcher` config option lets us
  swap in (a) a CDP-driven chromium fetch (Colt already runs chromium
  via `chrome_remote_interface` for page rendering — see
  `feedback project_cdp_vs_wallaby_tradeoff`), (b) an external CF-solving
  proxy, or (c) a request to Sodra for an allowlisted IP/UA. Until one
  of those is in place, `Sodra.run/1` returns
  `{:error, :sodra_blocked_by_cloudflare}` cleanly without exploding the
  Oban job.

Anyone reading this in 6 months: if `atvira.sodra.lt` ever drops the CF
challenge for plain `Req`, the existing pipeline will Just Work — only
the fetcher module changes.

### Coverage estimate

| Source | Rows | Companies | Years | Notes |
|---|---|---|---|---|
| RC `JAR_IREGISTRUOTI.csv` | ~230k | 230k registered LEs (all forms) | live | Pipe-separated, UTF-8, 40 MB |
| RC `JAR_FA_RODIKLIAI_PLNA_2022.csv` | ~120k | ~120k filers | 2022 | Comma-separated CSV, 36 MB, ~50% of registered companies file each year |
| RC `JAR_FA_RODIKLIAI_BLNS_2022.csv` | ~120k | (same) | 2022 | Balance sheets — equity/assets, **no employee count** |
| Sodra `draudejai.zip` | ~quarterly per employer | ~120k employers | 2009→now | Per-employer monthly insured count + avg salary |
| Sodra `apdraustuju_pajamu_analize.zip` | larger | analytics | monthly | Distribution / income analysis |

**Revenue coverage:** every limited company that actually filed for the
year. Mandatory since 2004, in practice ~50% of registered entities are
non-dormant filers in any given year. Same shape as Latvia.

**Employee coverage (Sodra, once downloader works):** ~100% of active
employers — Sodra collection is mandatory.

## Sources

### Registrų centras — basic registry (dataset 1484)

- Dataset page: https://data.gov.lt/datasets/1484/
- **Direct CSV** (no auth, daily refresh):
  `https://www.registrucentras.lt/aduomenys/?byla=JAR_IREGISTRUOTI.csv`
- Licence: CC-BY 4.0
- Format: `|`-delimited, UTF-8, ~40 MB, ~230k rows
- Columns (verified 2026-05-28):
  ```
  ja_kodas|ja_pavadinimas|adresas|ja_reg_data|form_kodas|form_pavadinimas|stat_kodas|stat_pavadinimas|stat_data_nuo|formavimo_data
  ```
- Sample row:
  ```
  110003978|"Uždaroji akcinė bendrovė ""Lietkompexim"""|Vilnius, S. Stanevičiaus g. 95, LT-07114|1991-04-25|310|Uždaroji akcinė bendrovė|0|Teisinis stat neįregistruotas|2025-03-04|2026-05-27
  ```
- Field mapping → `Company`:
  - `ja_kodas` → `registry_code` (numeric, 8-9 digits)
  - `ja_pavadinimas` → `name` (often double-quote-escaped)
  - `adresas` → parsed prefix → `region` (first comma-segment, e.g. "Vilnius")
  - `stat_kodas` → `status` (see status mapping below)
  - `form_kodas` → kept as auxiliary (310 = UAB, 320 = AB, 110 = IĮ, …)
  - `industry_code` → **`nil`**, see "NACE gap" below.

#### Status mapping

`stat_kodas` values observed:

| code | LT term | Maps to |
|---|---|---|
| `0` | Teisinis stat neįregistruotas (no registered legal status — i.e. operating normally) | `:registered` |
| `1`, `2`, `3` | Likviduojama / Bankrotas / Bankrutavusi (liquidation / bankruptcy stages) | `:liquidation` |
| `4`, `5` | Išregistruota / Reorganizuota | `:deleted` |
| anything else | | `:other` |

Verify the exact code-to-label mapping at runtime by checking `stat_pavadinimas`
strings; this column is the canonical text label.

### Registrų centras — profit/loss statements (dataset 1666)

- Dataset page: https://data.gov.lt/datasets/1666/
- **Direct CSV per fiscal year** (refreshed weekly):
  `https://www.registrucentras.lt/aduomenys/?byla=JAR_FA_RODIKLIAI_PLNA_{YEAR}.csv`
  for `{YEAR}` in 2015..2022 (latest published year as of 2026-05-28).
- Licence: CC-BY 4.0
- Format: comma-separated CSV, UTF-8, ~36 MB/year, ~120k rows/year
- Columns (verified for 2022):
  ```
  obj_kodas,obj_pav,form_kodas,form_pav,stat_statusas,stat_pav,
  template_id,template_name,standard_id,standard_name,
  laikotarpis_nuo,laikotarpis_iki,reg_date,
  pelnas_pries_apmokestinima,grynasis_pelnas,pardavimo_pajamos,formavimo_data
  ```
- Sample row:
  ```
  301011561,"UAB ""Rustela""",310,Uždaroji akcinė bendrovė,0,Teisinis stat neįregistruotas,FS0129,"Mažų ir labai mažų įmonių, netaikančių išimčių, finansinių ataskaitų rinkinys",IST024,PELNO (NUOSTOLIŲ) ATASKAITA,2021-01-01,2021-12-31,2022-01-02,-91,-91,,2023-03-01
  ```
- Field mapping → `AnnualReport`:
  - `obj_kodas` → join to `Company.registry_code`
  - `laikotarpis_iki` → year (take `String.slice(0, 4)`)
  - `pardavimo_pajamos` → `revenue_eur` (EUR, integer-encoded in CSV;
    NOT thousands — verified by spot-check against a sample where the
    company is known, and consistent with the small-company report
    forms reporting EUR units since the 2015 EUR adoption)
  - `employees` → **`nil`** (RC does not publish headcount; comes from Sodra)
  - `source: :rc`
- **Multiple rows per (company, year) are possible** when a company
  amends a filing. The pipeline keeps the latest `reg_date` per
  `(obj_kodas, laikotarpis_iki[0..3])`, same idea as RIK's
  `esitatud_kpv`.
- **Negative or empty `pardavimo_pajamos`** rows happen — many small
  companies file a tax-only return without revenue (e.g. holding
  companies). These get `revenue_eur = nil`; the row is still inserted
  with `source: :rc` and `employees: nil` so the company shows up
  in the "filed for year N" set.

### Registrų centras — balance sheets (dataset 1806) — NOT INGESTED

- File pattern: `JAR_FA_RODIKLIAI_BLNS_{YEAR}.csv`
- Contains `nuosavas_kapitalas` (equity), `ilgalaikis_turtas`,
  `trumpalaikis_turtas`, etc. — useful for "balance-sheet size" filtering
  but **no employee count**.
- Out of scope for this phase. Add later if a filter needs it.

### Sodra — per-employer monthly headcount (dataset 1510)

- Dataset page: https://data.gov.lt/datasets/1510/
- File URLs (all behind Cloudflare interactive challenge):
  - `https://atvira.sodra.lt/downloads/lt-eur/draudejai.zip` — per-employer aggregate
  - `https://atvira.sodra.lt/downloads/lt-eur/apdraustieji_det.zip` — detailed per-employer per-month
  - `https://atvira.sodra.lt/downloads/lt-eur/apdraustuju_pajamu_analize.zip` — income analysis (banded)
- Licence: CC-BY 4.0
- Format: zipped CSV(s). The per-employer file is documented to contain
  monthly rows with company code (`juridinio asmens kodas`), insured-persons
  count, average insured income (≈ avg gross salary). **Schema verification
  is deferred** until the fetcher is wired — Phase A could not download
  the file (see "Cloudflare blocker" below).

#### Cloudflare blocker

Verified 2026-05-28:

| Client | Result |
|---|---|
| `curl` + browser headers | 403, `cf-mitigated: challenge` |
| `curl-impersonate` / `curl_cffi` `chrome124` (TLS fingerprint) | 403 |
| `cloudscraper` (Python) | 403 |
| `chromium --headless=new` | hit "Just a moment…" CF holding page |

The challenge is the managed `cf-mitigated: challenge` variant, not the
"Under attack mode" + JS-eval one, so a fully-rendered Chromium with a
plausible profile *will* pass it given a few seconds; vanilla TLS clients
won't. Three options for production:

1. **CDP fetch through Colt's existing chromium.** Colt already runs a
   persistent Chromium for page rendering. Add a `Sodra.Download` strategy
   that opens a tab to `https://atvira.sodra.lt/`, waits for the CF token
   cookie to settle, then issues the file request via `fetch()` from
   inside the page (or downloads via `Page.setDownloadBehavior`). Highest
   reuse with existing infra; ~one extra service module.
2. **External CF-solving proxy** (Bright Data, ScraperAPI, FlareSolverr
   self-hosted). Adds a paid dependency, but isolates the workaround.
3. **Request whitelisting** by email to `info@sodra.lt`. They have a
   public open-data mandate and CC-BY licence; a written request stating
   intended use is reasonable. Slow but free and clean.

Recommendation: **(1) for prod, (3) in parallel.** This document
intentionally does *not* commit to a specific fetcher — the ingest
module accepts a `:fetcher` callable in opts, defaulting to a no-op that
returns `{:error, :sodra_blocked_by_cloudflare}`. Phase D will verify
the RC pipeline only; Sodra schema verification is a follow-up once
fetcher option 1 or 3 is in place.

### NACE / industry gap

JAR `iregistruoti` does **not** include EVRK (Lithuanian NACE-equivalent)
codes. The Lithuanian statistics office (Valstybės duomenų agentūra)
publishes them as data.gov.lt dataset **2088** (Saugyklos API at
`get.data.gov.lt/datasets/gov/lsd/ja_asmenys/JaAsmuo`), but that endpoint
timed out during Phase A probing from the dev box — likely needs an
authenticated partner API token. Same shape as Latvia's NACE gap. For
now LT companies are ingested with `industry_code = nil`; the NACE
filter in `Company.filtered` will not match them. Follow-up: either get
a data.gov.lt partner token (free, requires email) or scrape from the
JAR website.

## Pipeline architecture

Two independent services with one Oban worker each. Keeping them
separate (vs. combining behind `Colt.Services.Ingest.Lt`) because:

- They publish on different cadences (RC weekly, Sodra monthly) — wiring
  them into the same cron implies a coupling that doesn't exist.
- Sodra failures (CF blocker) must not abort the RC ingest.
- `from:` resume semantics stay clean within each service.

```
Colt.Services.Ingest.Lt.Rc           Colt.Services.Ingest.Lt.Sodra
├── Download (4 CSVs)                ├── Download (1-2 ZIPs via fetcher)
├── CompaniesImport (JAR base)       └── HeadcountImport
└── AnnualReports                        (writes AnnualReport rows
    (source: :rc)                         with source: :sodra)
```

### Why separate `AnnualReport` rows for Sodra vs UPDATE

`AnnualReport` has a `(company_id, year)` identity. The natural shape
would be:

- **Option A** — one row per (company, year), `source` set to whichever
  filing came in last. `revenue_eur` from RC, `employees` from Sodra,
  both fields nullable.
- **Option B** — two rows per (company, year), one with `source: :rc`
  carrying `revenue_eur`, one with `source: :sodra` carrying `employees`.
  Identity would have to be `(company_id, year, source)`.

`(company_id, year)` is the existing identity, used by EE and FI. Schema
changes are out of scope for this phase.

**This pipeline goes with Option A.** Sodra import is implemented as an
`UPDATE` on the existing `(company_id, year)` row, setting
`employees` and rewriting `source: :sodra` when RC didn't fill `employees`
(which it never does — RC has no headcount). If no RC row exists for that
(company, year) yet, Sodra inserts a fresh row with `revenue_eur: nil`,
`employees: <count>`, `source: :sodra`. The `Sodra.HeadcountImport` raw
SQL is `INSERT … ON CONFLICT (company_id, year) DO UPDATE SET employees
= EXCLUDED.employees, source = CASE WHEN annual_reports.revenue_eur IS
NOT NULL THEN annual_reports.source ELSE EXCLUDED.source END`.

(If we later need provenance on both fields independently, that's a
schema migration — out of scope here. Captured for follow-up.)

### `GrowthRollup` reuse

EE's `Rik.GrowthRollup` projects `revenue_latest`, `employees_latest`,
and `revenue_growth_bucket` from the latest two `AnnualReport` rows
per company. It's market-agnostic (filters by company's annual_reports,
not by source) and will pick up LT rows automatically once both Rc and
Sodra ran. Schedule it as the last step of LT ingest by simply calling
`Colt.Services.Ingest.Ee.Rik.GrowthRollup.run/0` — or extract into a
shared module if that bothers anyone.

This plan calls the existing module directly; refactor when a third
country wants it.

## Code modules

```
lib/colt/services/ingest/lt/rc.ex                # orchestrator, run(opts)
lib/colt/services/ingest/lt/rc/download.ex       # 4 CSVs from registrucentras.lt
lib/colt/services/ingest/lt/rc/companies_import.ex
lib/colt/services/ingest/lt/rc/annual_reports.ex # source: :rc
lib/colt/services/ingest/lt/sodra.ex             # orchestrator
lib/colt/services/ingest/lt/sodra/download.ex    # plug-in fetcher
lib/colt/services/ingest/lt/sodra/headcount_import.ex
lib/colt/jobs/rc_lt_ingest.ex                    # Oban worker, queue :registry
lib/colt/jobs/sodra_lt_ingest.ex                 # Oban worker, queue :registry
```

Cache directory config (add to `config/config.exs`):

```elixir
config :colt,
  rc_lt_cache_dir: "priv/ingest_cache_lt_rc",
  sodra_lt_cache_dir: "priv/ingest_cache_lt_sodra"
```

## Oban cron lines

Add these to `config/config.exs` `:crontab` (next to the RIK and PRH
crons; user wires these by hand per project rules):

```elixir
# RC (Lithuania) — basic registry + revenue, weekly Mondays 03:00 UTC
{"0 3 * * 1", Colt.Jobs.RcLtIngest},

# Sodra (Lithuania) — headcount, monthly 1st 04:00 UTC
{"0 4 1 * *", Colt.Jobs.SodraLtIngest},
```

## Verification (Phase D)

```sh
# RC slice
mix run -e 'Colt.Services.Ingest.Lt.Rc.run(limit: 1000) |> IO.inspect()'

# spot-check
docker exec -ti postgres psql -U postgres -d colt_dev -c "
  SELECT c.registry_code, c.name, c.status, ar.year, ar.revenue_eur, ar.employees, ar.source
  FROM companies c LEFT JOIN annual_reports ar ON ar.company_id = c.id
  WHERE c.market = 'lt'
  ORDER BY c.inserted_at DESC LIMIT 20;"
```

Sodra slice is deferred until the fetcher option is decided.

## Open follow-ups

1. **Sodra fetcher**: pick option 1 (CDP) or 3 (allowlist) and implement.
2. **NACE/EVRK**: data.gov.lt partner API key + dataset 2088 ingest.
3. **`AnnualReport.source` multi-provenance**: if a UI ever needs to
   show "revenue from RC, headcount from Sodra" separately, migrate to a
   per-field source tag.
