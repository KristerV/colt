# Latvia — Uzņēmumu reģistrs (UR) ingest

## Summary

**Better than the data-sources.md guess.** The Latvian Enterprise Register
(Uzņēmumu reģistrs, "UR") publishes the full bulk dump of basic registry
data **and** the financial data from every filed annual report — companies'
own submissions to VID/EDS that VID forwards to UR — as daily CC0-1.0 CSVs
on the national open-data portal.

That gives us exact `revenue_eur` (net turnover) and exact `employees`
(average headcount during the period) for the vast majority of Latvian
limited companies, free, no login. Coverage is the same shape as EE/RIK:
"every entity required to file an annual report has one in the dump for
each fiscal year submitted".

**NACE is no longer a gap.** This doc previously said NACE was "recorded by
VID but not exposed as a bulk download" and called it "the one real gap".
**That was wrong.** VID publishes it as free bulk CC0-1.0 open data on the
same portal, in `pdb_nm_komersantu_samaksato_nodoklu_kopsumas_odata.csv` —
a dataset titled about *paid taxes* that never mentions NACE in its name or
description, which is why it reads as unrelated. It carries
`Pamatdarbibas_NACE_kods` (principal activity, 4-digit) keyed by
`Registracijas_kods`, joining straight to `register.csv`'s `regcode`. No
scraping, no Lursoft licence, no LLM inference. Stage 4 (`IndustryCodes`)
imports it.

What we still **don't** get for free:

- **NACE for non-*komersanti*.** The VID file covers commercial entities
  only, so associations (26k active), farms (23k), individual undertakings
  (10k), foundations and media outlets get nothing — 0%, by construction.
  Verified there is no free bulk alternative: UR's
  `biedribu-un-nodibinajumu-darbibas-jomas` is an 80-value Latvian NPO label
  vocabulary, not NACE; CSP publishes no company-level file (its per-regnr
  lookup at `e.csp.gov.lv` is `Disallow: /` in robots.txt and enumeration-
  proof); Lursoft is quote-only with unconfirmed non-merchant scope.
  Accepted: these are largely not sales targets, and CSP shows associations
  collapse to `9499` ("organisations n.e.c.") anyway.
- Some non-merchant entities (associations, foundations, religious orgs)
  appear in `register.csv` but never file revenue-bearing annual reports;
  they end up in the DB with no `AnnualReport` rows. That's the same as
  Estonia and is correct.

## Sources

| File | URL | Size | License | Update |
|---|---|---|---|---|
| `register.csv` | https://data.gov.lv/dati/dataset/4de9697f-850b-45ec-8bba-61fa09ce932f/resource/25e80bf3-f107-4ab4-89ef-251b5b9374e9/download/register.csv | 122 MiB | CC0-1.0 | daily |
| `financial_statements.csv` | https://data.gov.lv/dati/dataset/8d31b878-536a-44aa-a013-8bc6b669d477/resource/27fcc5ec-c63b-4bfd-bb08-01f073a52d04/download/financial_statements.csv | 192 MiB | CC0-1.0 | daily |
| `income_statements.csv` | https://data.gov.lv/dati/dataset/8d31b878-536a-44aa-a013-8bc6b669d477/resource/d5fd17ef-d32e-40cb-8399-82b780095af0/download/income_statements.csv | 139 MiB | CC0-1.0 | daily |
| `vid_taxes_3y.csv` | https://data.gov.lv/dati/dataset/5ed74664-b49d-4b28-aacb-040931646e9b/resource/a42d6e8c-1768-4939-ba9b-7700d4f1dd3a/download/pdb_nm_komersantu_samaksato_nodoklu_kopsumas_odata.csv | 65 MiB | CC0-1.0 | **annual** (~April) |

Note the last one is published by **VID**, not UR, and on a much slower
cadence than UR's three: annual, refreshed around April with a rolling
three-year window. As of 2026-07 it still holds tax years 2022–2024 (last
refreshed 2025-04-03), so NACE lags the rest of the LV data by design.

Auth: **none**. Plain HTTPS GET, anonymous, no API key.

Reference docs:
- Open-data portal page: https://data.gov.lv/dati/eng/dataset/gada-parskatu-finansu-dati
- Field explanations XLSX: https://dati.ur.gov.lv/financial_data/Finansu_datu_lauku_skaidrojumi.xlsx
- ERD: https://dati.ur.gov.lv/financial_data/financial_data_erd.png

## Sample records

`register.csv` (`;` separator, UTF-8 with BOM, 21 cols):

```
regcode;sepa;name;name_before_quotes;name_in_quotes;name_after_quotes;without_quotes;regtype;regtype_text;type;type_text;registered;terminated;closed;address;index;addressid;region;city;atvk;reregistration_term
40008234596;LV49ZZZ40008234596;"""House of Glory""";"";House of Glory;"";0;B;Biedrību un nodibinājumu reģistrs;BDR;Biedrība;2015-03-02;; ;Rīga, Latgales iela 180 - 5;1019;112303082;0;100003003;"";
41502039692;LV03ZZZ41502039692;"IK ""D.Luxe""";IK;D.Luxe;"";0;K;Komercreģistrs;IK;Individuālais komersants;2020-03-05;; ;Daugavpils, Aroniju iela 66;5414;105057694;0;100003011;0050000;
```

Used columns: `regcode`, `name`, `type` (SIA/AS/IK/B/…), `address`,
`registered`, `terminated`. `terminated` non-empty → `:deleted`,
empty → `:registered`.

`financial_statements.csv` (`;` separator, ~22 cols incl. balance pointers):

```
id;file_id;legal_entity_registration_number;source_schema;source_type;year;year_started_on;year_ended_on;employees;rounded_to_nearest;currency;created_at
709391;16544392;40103466358;DokGPUIENv1;UGP;2016;2016-01-01;2016-12-31;1;ONES;EUR;…
709392;16544401;40103476182;DokGPUIENv1;UGP;2016;2016-01-01;2016-12-31;2;ONES;EUR;…
709393;16544404;40103863270;DokUGP2008v1;;2015;2015-01-21;2015-12-31;5;ONES;EUR;…
```

This file is the **statement header**: `id` (a/k/a `statement_id`),
`legal_entity_registration_number` (= `regcode`), `year`, `employees`
(integer; average count for the period), `currency` (EUR since 2014,
LVL pre-2014 — we filter `currency = 'EUR'`).

`income_statements.csv` (joined via `statement_id`):

```
statement_id;file_id;net_turnover;…;net_income
709391;16544392;0;…
709392;16544401;37688;…
709393;16544404;9275;…
```

We use `net_turnover` for `revenue_eur`. Units already in EUR (subject to
`rounded_to_nearest` — we only join rows where the header says `ONES`,
which is the vast majority; the rest are negligible).

## Pipeline stages (mapped to EE/RIK)

| Stage | EE module | LV module | Notes |
|---|---|---|---|
| 1 | `Ee.Rik.Download` | `Lv.Ur.Download` | Plain HTTPS GET, no zip; smaller files than EE. |
| 2 | `Ee.Rik.CompaniesImport` | `Lv.Ur.CompaniesImport` | Per-row Ash `upsert_basic` (≈300k rows; fine without raw SQL — same as EE). |
| 3 | `Ee.Rik.AnnualReports` | `Lv.Ur.AnnualReports` | **Two-file join.** Stream `financial_statements.csv` to build `%{statement_id => %{regcode, year, employees}}` for the latest N years, then stream `income_statements.csv`, look up by `statement_id`, emit raw-SQL `unnest` inserts with `ON CONFLICT DO NOTHING`. |
| 4 | `Ee.Rik.GrowthRollup` | reuse `Ee.Rik.GrowthRollup.run/0` | The rollup SQL is market-agnostic (works on `annual_reports` table). No per-country code needed. |

## Estimated row counts (2026-05)

| Set | Approx rows | Source |
|---|---|---|
| `register.csv` total entities | ~480k | including liquidated, religious, etc. |
| Of which active limited companies (SIA, AS, IK, …) | ~250k | the addressable B2B set |
| `financial_statements.csv` rows | ~3.5–4 M | one per filed year per entity (1996→present) |
| `income_statements.csv` rows | similar | one-to-one with statements |
| Reports we keep (last 3 years, EUR, with revenue) | ~600–800k | after filter |

## What goes into our `companies` table

| Column | Source | Notes |
|---|---|---|
| `registry_code` | `regcode` | 11-digit numeric |
| `market` | `:lv` | enum already present |
| `name` | `name` | UR includes the quoted variants; we use the full `name` |
| `region` | `address` first segment | e.g. "Rīga", "Daugavpils", "Liepāja"; cheap split on `,` |
| `status` | derived | `terminated` non-empty → `:deleted`, else `:registered`; pre-merchant types stay `:other` |
| `industry_code` | `Pamatdarbibas_NACE_kods` (VID) | NACE **Rev. 2.1**, 4-digit, newest tax year per company; `nil` for the 23 reused codes filed under Rev. 2. See below. |

## Coverage estimate vs spec §3.1 targets

| Field | Free coverage | Quality |
|---|---|---|
| Identity (code, name, status, address) | ~100% | exact |
| Revenue (`revenue_latest`) | ~70–80% of active limited cos | exact EUR, lags 12–18 months |
| Employees (`employees_latest`) | ~70–80% | exact integer (average for the period) |
| Industry / NACE | **83.8% of active SIA** (28.6% of all rows) | exact, NACE Rev. 2.1; lags ~18 months |
| Generic email | not in UR open data | enrichment path (already exists in code) |
| Website | not in UR open data | enrichment path |

## NACE (`industry_code`)

Read `docs/countries/industry-codes.md` first — Latvia is the **revision-known**
case (Estonia's category): the **tax year is the classifier version**, so
collisions are only ambiguous on the old rows. Measured against the real file
(2026-07-14):

| Funnel | Rows |
|---|---|
| LV rows in `companies` | 485,896 |
| …still active | 219,865 |
| …present in the VID file with a 4-digit NACE | 150,652 |
| …surviving translation | 139,831 |
| …matching a row in our table | **138,856** |

So **28.6% of the LV table**, but the losses are structural: 266k terminated
entities and ~60k non-*komersanti* were never going to have a code. Against
the addressable set: **active SIA 83.8%** (115,634 / 138,031), active IK 66.8%,
all active companies 57.0%.

Rule-4 partition proving the revision boundary (playbook §Rule 4):

| year | rev2-only | rev21-only | both |
|---|---|---|---|
| 2022 | 48,000 | **0** | 86,586 |
| 2023 | 50,221 | **0** | 91,006 |
| 2024 | **429** | 41,448 | 76,580 |

2022/23 hold zero Rev-2.1-only codes → they are Rev. 2. But 2024 is *not*
purely Rev. 2.1: 429 rows still carry a Rev-2-only class, so `IndustryCodes`
treats a Rev-2-only code as Rev. 2 regardless of its year. Every code in the
file is valid in one revision or the other — there are no junk codes.

10,821 companies (7.2% of those with a code) drop to `nil`: their class is one
of the 23 reused between revisions *and* was filed under Rev. 2, making it
genuinely undecidable. They heal when VID reissues under Rev. 2.1.

In ranking terms: Latvia is closer to Estonia/Norway than the
`data-sources.md` table claimed. The "Lursoft monetises the gap" framing
is mostly about industry/NACE, beneficial-owner enrichment, and historical
deep dives — not the core revenue+employees signal.

## Things we deliberately don't import (yet)

- `balance_sheets.csv` (139 MiB) — full balance sheet line items. Not used
  by Liid funnel filters. Adding it is a 30-min copy of the income-statement
  stage if we ever want net worth / total assets.
- `cash_flow_statements.csv` — same.
- Beneficial-owners (PLG) dataset, sanctions dataset, shareholders dataset
  — all CC0-free; future enrichment phases.
- `area_of_activity.csv` (free-text purpose strings, no NACE).

## For the user — wiring

**Oban cron line** to add to `config/config.exs` under the `crontab:` list,
verbatim:

```elixir
{"0 5 1 * *", Colt.Jobs.UrIngest},
```

Monthly, 05:00 UTC on the 1st of every month — staggered after the EE
(03:00) and FI (04:00) runs to avoid overlapping the `:registry` queue
(concurrency 1). UR publishes daily; monthly is sufficient for our purposes
and matches the cadence we use for EE/FI.

**Enum delta**: none. `:lv` already on `Company.market`, `:ur` already on
`AnnualReport.source`.

**Cache directory**: a new `config/config.exs` entry alongside the existing
`rik_ee_cache_dir` and `prh_fi_cache_dir`:

```elixir
ur_lv_cache_dir: "priv/ingest_cache_lv",
```

## Manual run

```bash
# Full run
mix run -e "Colt.Services.Ingest.Lv.Ur.run()"

# Resume from stage N (1=download, 2=companies, 3=annual reports, 4=growth)
mix run -e "Colt.Services.Ingest.Lv.Ur.run(from: 3)"

# Or via Oban
mix run -e "Colt.Jobs.UrIngest.schedule()"
```
