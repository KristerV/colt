# Denmark — CVR / Virk

**Status: ✅ shipped, no auth, no payment.** Free programmatic bulk path
via the public `distribution.virk.dk/offentliggoerelser` Elasticsearch
endpoint plus per-filing XBRL fetches from `regnskaber.virk.dk`. Both
documented as free public services by Erhvervsstyrelsen.

Coverage trade-off (read this before evaluating Liid's DK filters):
- **Identity (CVR, name, address)**: ~660k limited-company entities — every
  DK company that has filed at least one annual report. Matches the
  expected ~600–700k active limited-company universe.
- **Industry code (NACE / branchekode)**: **not available** without the
  3-week-approval system-til-system CVR credentials. `industry_code` is
  left `nil` for `market = :dk`. Industry filters will treat all DK
  companies as "no industry assigned".
- **Employees (AverageNumberOfEmployees)**: ~81% of recent filings.
- **Revenue (fsa:Revenue / ifrs-full:Revenue)**: ~12% of recent filings
  — only Class C+ and IFRS filers. Class B SMEs (the bulk of DK
  companies) legally hide Revenue and report only GrossProfitLoss. We
  do **NOT** populate `revenue_eur` from GrossProfit (different concept,
  documented decision below).

If the product needs better revenue coverage for DK, the only paths are:
1. Apply for system-til-system CVR access (free, 3-week wait) to pull
   industry + status from the gated `cvr-permanent` index.
2. Add a GrossProfit field (or fallback `revenue_eur = gross_profit`
   with a confidence flag, requires schema change).

Neither is in scope for phase A.

---

## Sources

### 1. Annual report index — `distribution.virk.dk/offentliggoerelser`

`http://distribution.virk.dk/offentliggoerelser/_search` — public
Elasticsearch (v6.8), JSON, **no auth, no key**, no rate-limit headers
observed.

Verified live 2026-05-28:
- Mapping at `http://distribution.virk.dk/offentliggoerelser`
- 6,265,213 total filings; 659,586 unique CVR numbers
- Bulk-iterable via the `scroll=Nm` parameter (default Elastic scroll;
  `max_result_window: 3000` blocks deep `from`, scroll bypasses it)

Sample document:

```json
{
  "_id": "urn:ofk:oid:9366144",
  "_source": {
    "cvrNummer": 10204534,
    "sagsNummer": "13-21.086",
    "offentliggoerelsestype": "regnskab",
    "offentliggoerelsesTidspunkt": "2013-05-30T22:00:00.000Z",
    "regnskab": {
      "regnskabsperiode": {"startDato": "2012-01-01", "slutDato": "2012-12-31"}
    },
    "dokumenter": [
      {"dokumentType": "AARSRAPPORT", "dokumentMimeType": "application/xml",
       "dokumentUrl": "http://regnskaber.virk.dk/43540201/Y3ZyL...ZQ.xml"},
      {"dokumentType": "AARSRAPPORT", "dokumentMimeType": "application/pdf",
       "dokumentUrl": "http://regnskaber.virk.dk/43540201/Y3ZyL...ZQ.pdf"}
    ]
  }
}
```

Field meanings:
- `cvrNummer` — 8-digit Danish company number. This is our `registry_code`.
- `regnskab.regnskabsperiode.slutDato` — fiscal year end (ISO date).
- `dokumenter[].dokumentUrl` — public URL of the XBRL XML (gzip-encoded
  HTTP response, `Content-Type: text/xml`, `Content-Encoding: gzip`).
- `offentliggoerelsestype` — filter to `regnskab` (annual report). Other
  values include `aktivitetspligt`, `aktionaerregister`, etc.

Distribution per fiscal year (verified):

| FY end       | Filings |
| ------------ | ------- |
| FY2023       | 345,854 |
| FY2024       | 353,415 |
| FY2025 (YTD) | 208,055 |

### 2. Per-filing XBRL — `regnskaber.virk.dk`

`http://regnskaber.virk.dk/{sagsNummer}/{base64}.xml` — public, gzipped
XBRL XML. Verified at ~5–250 KB per file (mean ~15 KB for Class B,
~250 KB for IFRS filers). No auth, no key.

Three taxonomy variants are in active use:

1. **Old DCCA GAAP (~pre-2018)**: `xmlns:EOGS80000=".../fsa"` prefix.
   Fields like `EOGS80000:GrossProfitLoss`, `EOGS80000:ProfitLoss`.
2. **Current DCCA GAAP (2018-present)**: `xmlns:fsa="http://xbrl.dcca.dk/fsa"`
   prefix. Fields like `fsa:Revenue`, `fsa:GrossProfitLoss`,
   `fsa:AverageNumberOfEmployees`, `fsa:ClassOfReportingEntity`.
3. **ESEF / IFRS (listed companies)**: `xmlns:ifrs-full=".../ifrs-full"`
   prefix. Field `ifrs-full:Revenue`. Plus the Danish FSA taxonomy
   carries `fsa:AverageNumberOfEmployees` alongside the IFRS body.

The CVR identity, name, and address always live in the `gsd:` namespace:
- `gsd:IdentificationNumberCvrOfReportingEntity` — CVR (matches the
  `cvrNummer` from the metadata; verify equality, defensive).
- `gsd:NameOfReportingEntity` — legal name.
- `gsd:AddressOfReportingEntityStreetName`,
  `gsd:AddressOfReportingEntityStreetBuildingIdentifier`,
  `gsd:AddressOfReportingEntityPostCodeIdentifier`,
  `gsd:AddressOfReportingEntityDistrictName` — address parts.

Older taxonomy uses `EOGS10000:NameOfReportingEntity` and
`EOGS10000:AddressOfReportingEntityStreetAndNumber` /
`EOGS10000:AddressOfReportingEntityPostcodeAndTown`. The ingest parser
matches both via namespace-agnostic regex (`<[a-z0-9]+:NameOfReportingEntity`).

### 3. What requires login (NOT used)

- `distribution.virk.dk/cvr-permanent/virksomhed/_search` — full company
  registry, including industry code, status, all addresses, even for
  dormant CVR numbers. **HTTP 401** without basic-auth credentials.
  Free application via `cvrselvbetjening@erst.dk`, ~3-week processing.
  See `docs/spec.md` §3.2 for how to wire user-supplied credentials
  later if the product needs DK industry filters.

---

## Currency & units

XBRL values for all monetary facts are reported in **DKK** (`unit u0` →
`<measure>iso4217:DKK</measure>`). Verified across all sample filings.

DKK is pegged to EUR under ERM II (band ±2.25%, in practice ±0.5%).
Conversion to EUR uses a fixed module attribute:

```elixir
@dkk_to_eur 0.134
```

Source: ECB ref ~7.46 DKK/EUR as of 2026-05; pegged target 7.46038.
Drift since 2000 has been <1%, so a constant is fine for revenue-band
bucketing. Refresh if the peg ever breaks.

**Employees**: `fsa:AverageNumberOfEmployees` is an integer in `unitRef="pure"`.
Stored directly as `employees`.

---

## Pipeline stages

Mapped to EE/RIK:

| Stage | EE/RIK module                | DK/CVR module                                       |
| ----- | ---------------------------- | --------------------------------------------------- |
| 1     | `Download`                   | `Dk.Cvr.Download` — no-op (no bulk file; metadata + XBRL are fetched in stage 3) |
| 2     | `CompaniesImport`            | folded into stage 3 (each XBRL contributes name + address; no upstream company list) |
| 3     | `CompanyDetails`             | skipped (no website / generic email in XBRL or in the public regnskaber feed) |
| 4     | `AnnualReports`              | `Dk.Cvr.AnnualReports` — scroll metadata, fetch XBRL, upsert company + report per filing |
| 5     | `GrowthRollup`               | `Dk.Cvr.GrowthRollup` — identical SQL to EE/FI      |

The orchestrator `Colt.Services.Ingest.Dk.Cvr.run/1` chains stages 1, 4,
5 (download is a placeholder to keep the staged-resume contract).

`Application.get_env(:colt, :ingest_max_years, 3)` controls how many
most-recent fiscal years to walk — matches FI/PRH semantics.

`Application.get_env(:colt, :cvr_dk_max_filings, nil)` caps total
filings per run (set in dev/CI to keep iterations cheap).

### Per-filing flow

1. ES scroll over `offentliggoerelsestype=regnskab` + `slutDato` range.
   Page size 200, scroll alive 5 min.
2. For each hit: extract `cvrNummer`, fiscal-year end, and the XBRL
   `dokumentUrl` (`dokumentMimeType=application/xml`,
   `dokumentType=AARSRAPPORT`).
3. Fetch + gunzip the XBRL. Parse with namespace-agnostic regex:
   `Revenue`, `AverageNumberOfEmployees`, `NameOfReportingEntity`, address.
4. Upsert `Company` via `:upsert_basic` (name + region from city, status
   defaults to `:registered`; we have no public liquidation signal here).
5. Upsert `AnnualReport` row when `revenue_eur` *or* `employees` is
   non-nil. The annual_reports table only stores `revenue_eur`; we
   convert DKK→EUR at ingest. A row with only `employees` carries a nil
   `revenue_eur` — handled by `growth_rollup`'s NULL guard.
6. Chunked raw-SQL `INSERT … ON CONFLICT DO NOTHING` per the
   `large-csv-ingest.md` playbook. Chunk size 500.

---

## Coverage estimate

Lower bound (only filings since FY2023, n=26 sample):

| Field            | Coverage     | Notes                                 |
| ---------------- | ------------ | ------------------------------------- |
| CVR + Name       | 100%         | always present in XBRL gsd: header    |
| Address          | ~95%         | rare older filings omit               |
| AverageNumberOfEmployees | ~81% | mandatory above micro threshold       |
| fsa:Revenue      | ~12%         | only Class C+ and IFRS filers         |
| GrossProfitLoss  | ~96%         | NOT used (different concept)          |

So a realistic Liid filter set for DK:
- **Employee filters**: usable, ~81% of last-3-year filers have a value.
- **Revenue filters**: degraded, ~12% have an exact figure. The other
  ~88% will have `revenue_latest = NULL` and be excluded from any
  `revenue_min/max` filter.
- **Industry filters**: zero coverage. DK companies will fail any
  industry-code filter (`fragment("LEFT(industry_code, 4)…")` against a
  NULL column).
- **Growth bucket**: only computable for the ~12% with two consecutive
  years of Revenue. Realistically maybe 5–8% of DK companies.

These limits should be surfaced in the campaign-filter UI for `:dk` if
they aren't already. Not in scope for this ingest phase.

---

## Throughput & sizing

Sample fetch timings (sequential, no parallelism, no rate-limit):

| Op                                | Wall time     |
| --------------------------------- | ------------- |
| ES scroll page (200 hits)         | 60–180 ms     |
| Per XBRL fetch + gunzip + parse   | 120–400 ms    |
| Bulk insert chunk (500 rows)      | 25–50 ms      |

Conservative end-to-end: **~3 filings/s sustained** on a single
connection (~250ms per XBRL × 1 conn). Per-year (~350k filings):
**~32 hours**. Full 3-year ingest: **~4 days**.

This is slow but free. The Oban worker has `timeout :infinity` and runs
on `:registry` queue with concurrency 1, so it doesn't block other work.

If 3-year scope becomes the constraint:
- Drop to 1 year (~32h) — recommended for first production run.
- Or apply for system-til-system creds and bulk-import the CVR registry
  (~5 min) plus walk only large companies' XBRL.

---

## Pipeline-stages divergence vs EE

Three intentional differences:

1. **No `Download` stage.** There is no daily DK bulk dump. Stage 1 is a
   no-op stub that returns `{:ok, :no_bulk_download}` to keep the
   orchestrator's resume-from-N contract intact.
2. **No `CompaniesImport` stage.** XBRL filings *are* the company source;
   each filing upserts its parent company alongside the AnnualReport
   row. This is folded into stage 4.
3. **No `CompanyDetails` stage.** XBRL has no website / generic email.
   Stage 3 is a no-op stub.

Stages 4 and 5 carry the real work.

---

## For the user

**Oban cron line** for `config/config.exs` (add after the existing
RIK/PRH lines around line 27):

```elixir
{"0 5 1 * *", Colt.Jobs.CvrIngest},
```

Cadence: monthly, on the 1st at 05:00 UTC. Same monthly slot as RIK/PRH
to keep the registry queue's load shape predictable; offset by an hour
so they don't all start simultaneously.

**Cache dir config** (already added — see `config/config.exs` change
proposal in the report):

```elixir
config :colt,
  ...,
  cvr_dk_cache_dir: "priv/ingest_cache_dk",
```

**Enum delta**: none required.
- `Company.market`: `:dk` already listed (line 230 of
  `lib/colt/resources/company.ex`).
- `AnnualReport.source`: `:cvr` already listed (line 48 of
  `lib/colt/resources/annual_report.ex`).

**DKK→EUR rate**: hard-coded as `@dkk_to_eur 0.134` in
`Colt.Services.Ingest.Dk.Cvr.AnnualReports`. Review annually; refresh
if DKK is repegged.

## Sources

- [CVR / Virk portal (English)](https://datacvr.virk.dk/data/?language=en-gb)
- [System-til-system regnskabsdata article](https://datacvr.virk.dk/artikel/system-til-system-adgang-til-regnskabsdata) — confirms `distribution.virk.dk/offentliggoerelser` is free & public, JSON+XBRL
- [Erhvervsstyrelsen Elasticsearch primer](https://erhvervsstyrelsen.dk/kom-godt-igang-med-elasticSearch) — auth-gated `cvr-permanent` is the *other* product
- [DCCA XBRL taxonomy entry points](http://archprod.service.eogs.dk/taxonomy/) — referenced from XBRL filings
- [filings.xbrl.org DK source](https://filings.xbrl.org/source/dk-virk) — third-party mirror, confirms taxonomies in use
