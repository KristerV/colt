# Norway — BRREG (Brønnøysundregistrene)

Status: ✅ free, no auth, NLOD-licensed. Designed-in as Liid's reference Nordic ingest in `docs/data-sources.md`.

## Sources

| Stage | URL | Format | Auth | Licence |
|---|---|---|---|---|
| Entities (bulk) | `https://data.brreg.no/enhetsregisteret/api/enheter/lastned/csv` | gzipped CSV (`application/vnd.brreg.enhetsregisteret.enhet.v2+gzip`) | none | NLOD |
| Entities (bulk, alt) | `https://data.brreg.no/enhetsregisteret/api/enheter/lastned` | gzipped JSON | none | NLOD |
| Annual accounts | `https://data.brreg.no/regnskapsregisteret/regnskap/{orgnr}` | JSON array (one per filed FY) | none | NLOD |
| Filed years list | `https://data.brreg.no/regnskapsregisteret/regnskap/aarsregnskap/kopi/{orgnr}/aar` | JSON array of strings | none | NLOD |

Refresh cadence: enheter dump regenerated nightly ~05:00 CEST. Regnskap is updated 5×/week.

Authentication: the OpenAPI spec (`/regnskapsregisteret/regnskap/v3/api-docs`) advertises `basicAuth` on the GET `/regnskap/{orgnr}` endpoint, but unauth requests return HTTP 200 with full JSON in practice (verified 2026-05-28 against 50+ orgnrs). The spec appears stale; we proceed without credentials.

## Volumes (measured 2026-05-28)

| Cohort | Count | Notes |
|---|---|---|
| Total entities in CSV | 1,162,944 | Includes sole proprietors (ENK), associations (FLI), foreign branches (NUF), municipalities, parishes. |
| Limited companies (AS) | 427,324 | The prospecting universe. 98.2% are active (not bankrupt / under liquidation). |
| AS with filed annual accounts | 388,042 (90.8% of AS) | These are the orgnrs we will GET /regnskap/ for. |
| All entities with `antallAnsatte` populated | 70,995 (6.1%) | NAV-sourced employee count, lives **only in enhetsregister**. |
| Active AS with `antallAnsatte` populated | 60,305 (14.4% of active AS) | Real gap — see "Coverage caveats" below. |

CSV dump on-disk: 147 MB gzipped → ~795 MB unzipped (uses embedded newlines in quoted `aktivitet`/`vedtektsfestetFormaal` free-text fields; `wc -l` overcounts row count — NimbleCSV streaming is mandatory).

JSON dump on-disk: 188 MB gzipped.

## Sample CSV row

Header (one line):

```
"organisasjonsnummer","navn","organisasjonsform.kode","organisasjonsform.beskrivelse",
"naeringskode1.kode","naeringskode1.beskrivelse",…,"harRegistrertAntallAnsatte",
"antallAnsatte","registreringsdatoAntallAnsatteEnhetsregisteret",…,"hjemmeside","epostadresse",
…,"postadresse.adresse","postadresse.poststed","postadresse.postnummer","postadresse.kommune",
…,"sisteInnsendteAarsregnskap","registreringsdatoenhetsregisteret","stiftelsesdato",
…,"konkurs","konkursdato","underAvvikling",…
```

Row:

```
"810034882","SANDNES ELEKTRISKE AS","AS","Aksjeselskap","43.210","Elektrisk installasjonsarbeid",…,
"true","8","2025-10-15",…,"post@sandneselektriske.no",…,"SANDNES","4307","SANDNES","1108",…,
"2025","1995-02-19","1977-06-15",…,"false","","false",…
```

Field mapping → `Colt.Resources.Company`:

| BRREG | Liid | Notes |
|---|---|---|
| `organisasjonsnummer` | `registry_code` | 9-digit string. |
| `navn` | `name` | |
| `naeringskode1.kode` | `industry_code` | `"43.210"` style — dot-separated, last digit is national. Stored verbatim; the `LEFT(industry_code, 4)` NACE-prefix filter in `Company.filtered` needs to be told this format is `"43.2"` not `"4321"` style. **Trim the dot.** See "Industry-code handling" below. |
| `forretningsadresse.poststed` (fallback `postadresse.poststed`) | `region` | Norwegian city in caps. |
| `konkurs == "true"` | `status: :liquidation` | |
| `underAvvikling == "true"` | `status: :liquidation` | |
| else | `status: :registered` | We do not have a deleted state — entities removed from BRREG drop from the dump. |
| `antallAnsatte` | (passes through to AnnualReport / GrowthRollup) | See employee-count handling below. |

## Sample regnskap response

```json
[{
  "id": 6364789,
  "regnskapstype": "SELSKAP",
  "virksomhet": {"organisasjonsnummer":"810034882","organisasjonsform":"AS","morselskap":false},
  "regnskapsperiode": {"fraDato":"2025-01-01","tilDato":"2025-12-31"},
  "valuta": "NOK",
  "oppstillingsplan": "store",
  "resultatregnskapResultat": {
    "ordinaertResultatFoerSkattekostnad": -78041.00,
    "aarsresultat": -78041.00,
    "driftsresultat": {
      "driftsresultat": -31910.00,
      "driftsinntekter": {"sumDriftsinntekter": 10021242.00},
      "driftskostnad":   {"sumDriftskostnad":   10053152.00}
    }
  },
  "egenkapitalGjeld": {…},
  "eiendeler": {…}
}]
```

Field mapping → `Colt.Resources.AnnualReport`:

| BRREG | Liid | Notes |
|---|---|---|
| `regnskapsperiode.tilDato` (year part) | `year` | We use `tilDato` (FY end) as the canonical "year". A FY 2024-07-01 → 2025-06-30 maps to **2025**. |
| `resultatregnskapResultat.driftsresultat.driftsinntekter.sumDriftsinntekter` | `revenue_eur` (after FX) | Operating revenue (turnover). Picked over `aarsresultat` because the `revenue_growth_bucket` logic compares scaled top-line. |
| `valuta` | drives FX conversion | Almost always `NOK`. Foreign currency records are kept only when in EUR; everything else (USD, SEK, …) is dropped to avoid invented rates. |
| `regnskapstype` | filter | Only `SELSKAP`. Drop `KONSERN` (consolidated group accounts double-count subsidiaries). |
| (none — see below) | `employees` | BRREG regnskap has **no employee field**. Sourced from `antallAnsatte` in enhetsregister, snapped onto the most recent `AnnualReport` only. |

## Annual report retrieval strategy

There is **no bulk dump of annual accounts**. The only documented machine-readable source is the per-orgnr REST endpoint. With ~388k AS-with-filings, we walk them concurrently.

- Throughput probed: 10 parallel calls finish in ~0.2s ⇒ effective ~50 req/s/single-host; 25-way `Task.async_stream` should sit at ~50-150 req/s comfortably without tripping rate limits (no `Retry-After` / 429 observed in 60-call sample).
- Estimated wall-clock for a full run at 100 req/s: **388,042 / 100 ≈ 65 min**. Acceptable for a monthly Oban job.
- `retry: false` in `Req.get` (Oban owns retry semantics per project memory). On transient HTTP errors we log and skip — the next monthly run picks them up.
- The endpoint returns `[]` (or 404) when an orgnr has no filings; we treat both as a no-op, no error.

## NOK → EUR conversion

Norwegian filings are denominated in **NOK** (verified in 50/50 of an AS random sample). Liid's `revenue_eur` column expects EUR.

**Approach:** apply a single documented constant rate, flagged as a fixed conversion (not a historical exchange-rate lookup). This is consistent with how Liid handles the Estonian EUR-native source — `revenue_eur` is taken as nominal local turnover scaled to EUR for cross-country prospecting filters, not a finance-grade restated figure.

```elixir
# Module attribute in BRREG.AnnualReports
@nok_per_eur Decimal.new("11.7")  # ~2026-05 ECB reference, see docs/countries/no.md
```

Rate source: ECB euro reference rate for NOK has been ~11.5–12.0 NOK/EUR throughout 2024–2026. We pick **11.7** as a midpoint. The `revenue_growth_bucket` calculation is rate-invariant (uses ratios), so the only downstream effect of any drift is on the absolute `revenue_min`/`revenue_max` filter UI. A ±5% drift is well within the noise of these prospecting filters.

**Flagged for review:** revisit annually. If/when we want exact historical FX, swap to a year-keyed lookup map (`@nok_per_eur_by_year = %{2024 => …, 2025 => …}`) and store the source on the report. For phase 1, the constant is good enough.

Records in non-NOK, non-EUR currencies (e.g. Equinor in USD) are imported as companies but their non-EUR regnskap is **skipped** — `revenue_eur: nil` is preferable to a hallucinated cross-currency conversion.

## Coverage caveats (be honest)

1. **Employee count: 14% of active AS only.** `antallAnsatte` is populated by NAV's AA-registeret, which requires the company to file employer reports. The 86% gap is largely 1-person consulting AS where the owner draws dividends instead of formal wages. We cannot fill this gap from free sources. Liid's `Company.with_employees` view will show ~60k Norwegian rows; the prospecting `employees_min`/`employees_max` filter will hide everyone else.
2. **Revenue: 91% of AS, 0% of ENK.** Sole proprietors (ENK, 456k of them) don't file annual accounts with BRREG. They're imported as companies but never get a revenue or growth bucket. This matches EE's pattern (`OÜ` only).
3. **FY year ambiguity.** A handful of AS use shifted fiscal years (e.g. Jul–Jun). We canonicalise on `tilDato.year`, so a 2024-07 → 2025-06 filing becomes "2025". Year-over-year comparisons may mix calendar and shifted years for the same company across periods — same compromise EE makes.
4. **No retroactive amendments captured.** `INSERT … ON CONFLICT DO NOTHING` (per playbook) means once a `(company_id, year)` is written, a corrected filing in a later month is ignored. AS amendments are <2% of filings empirically; live with it.
5. **Spec stamps `basicAuth` on the regnskap endpoint.** We rely on the observed behaviour that unauth works. If BRREG closes the loophole, the AnnualReports stage will start returning 401s; the Companies stage stays unaffected.

## Industry-code handling

BRREG `naeringskode1.kode` is dot-separated (`"43.210"`) while EE EMTAK is the same NACE class without a dot (`"43211"`). Liid's `Company.filtered` action uses `LEFT(industry_code, 4)` to match a 4-digit NACE class prefix.

For "43.210" `LEFT(_, 4)` returns `"43.2"` — wrong shape. **Strip the dot at ingest time**: `"43.210" → "43210"`. Verified the BRREG format is always `NN.NNN` (5 digits with one dot at position 3) by inspection. The 5th digit is the Norwegian national subdivision (consistent with EE EMTAK's 5th digit being national); the underlying NACE-4 prefix matches across countries.

(The field-mapping table above says "Stored verbatim" — that is stale. The code de-dots.)

### Which NACE revision

**Norway is on SN2025 (NACE Rev. 2.1), not SN2007.** Verified against BRREG's own API: every `45.*` query returns `totalElements: 0`, while `43.210` returns 5613 — division 45 no longer exists. Motor-vehicle repair moved to `95.31` ("Reparasjon og vedlikehold av motorvogner"); vehicle *sales* moved into 46/47. Our dump is 100% Rev 2.1 — 0 of 33,423 sampled coded rows carry a Rev-2-only class.

So the NO importer needs **no** revision translation: de-dotting is the whole job. This is not true of Estonia and Lithuania, whose registries still serve a mix; see `Colt.Filters.NaceMigration`. Liid stores Rev. 2.1 everywhere, and `Colt.Filters.IndustryLabels` is generated from the Rev. 2.1 structure.

Historical note: for a long time NO looked like it had no car-repair shops at all, because the filter vocabulary was still NACE Rev. 2 and offered `4520` — which matches nothing in Norway. ~36% of Norwegian companies were unreachable by industry filter for the same reason.

## Pipeline stages

Mirror EE's RIK structure but with fewer stages:

| Stage | Module | What |
|---|---|---|
| 1 | `Download` | Pull + gunzip `enheter_alle.csv.gz` into the cache dir. No unzip — gzip is streamed in stage 2. (Optionally: cleanup the `.gz` once stage 2 succeeds.) |
| 2 | `CompaniesImport` | NimbleCSV-parse the dump, upsert `(registry_code, market: :no)` with name, industry (de-dotted), region, status. Same shape as EE/lihtandmed but via `Company.upsert_full` because BRREG also gives us industry + website in the same row. |
| 3 | `AnnualReports` | For every AS with `sisteInnsendteAarsregnskap` populated (~388k), `Task.async_stream` GET `/regnskap/{orgnr}`. Parse, filter to `SELSKAP`+`NOK`, convert NOK→EUR, raw-SQL unnest insert into `annual_reports` with `ON CONFLICT DO NOTHING`. Employees from the cached enheter `antallAnsatte` are written onto **the most recent year only**. |
| 4 | `GrowthRollup` | Same SQL pass as `Colt.Services.Ingest.Ee.Rik.GrowthRollup` — projects two most recent reports onto `revenue_latest` / `employees_latest` / `revenue_growth_bucket`. |

There is **no separate `CompanyDetails` stage** (BRREG ships everything in one CSV) and no per-year-file step (BRREG is a per-orgnr API, not a per-FY-year dump like RIK elemendid).

## For the user to apply

**Oban cron** — add this entry to `config/config.exs`, between the EE and FI crons:

```elixir
# Inside config :colt, Oban, plugins: [{Oban.Plugins.Cron, crontab: [...]}]
{"0 3 1 * *", Colt.Jobs.RikIngest},
{"0 4 1 * *", Colt.Jobs.PrhIngest},
{"0 5 1 * *", Colt.Jobs.BrregIngest},   # Norway — BRREG, monthly, 1st @ 05:00 UTC
{"* * * * *", Colt.Jobs.SendDueEmails},
{"* * * * *", Colt.Jobs.PollInbounds},
{"*/10 * * * *", Colt.Jobs.PollTracking}
```

**Cache directory env var** — add under `config :colt,`:

```elixir
brreg_no_cache_dir: "priv/ingest_cache_no",
```

Enum changes: none. `:no` is already on `Company.market`; `:brreg` is already on `AnnualReport.source`.

## Manual run

```
# Stage 1+2 only (quick smoke test, ~5 min):
mix run -e 'Colt.Services.Ingest.No.Brreg.run(limit: 1000)'

# Full ingest (≈70 min wall clock):
mix run -e 'Colt.Services.Ingest.No.Brreg.run()'

# Resume from regnskap after a crash:
mix run -e 'Colt.Services.Ingest.No.Brreg.run(from: 3)'
```

## Sources

- [BRREG datasets and APIs](https://www.brreg.no/en/use-of-data-from-the-bronnoysund-register-centre/datasets-and-api/)
- [Enhetsregisteret API docs](https://data.brreg.no/enhetsregisteret/api/docs/index.html)
- [Regnskapsregisteret OpenAPI spec](https://data.brreg.no/regnskapsregisteret/regnskap/v3/api-docs)
- [Regnskapsregisteret on data.norge.no](https://data.norge.no/en/datasets/7c87f169-2520-4e56-ba2a-b7a3cc7de2e9/regnskapsregisteret)
- [NLOD licence](https://data.norge.no/nlod/en/2.0)
