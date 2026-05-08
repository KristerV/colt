# Per-country company data sources

Notes on what's freely available for each market we plan to support. Focus is on what we need: **company identity, industry code, yearly revenue, employee count.**

## Quick comparison

| Country | Registry | Revenue (free) | Headcount (free) | Access method | Notes |
|---|---|---|---|---|---|
| Estonia 🇪🇪 | RIK Avaandmed | Exact | Exact (avg) | **Bulk download only** (CSV/JSON) | Already integrated |
| Norway 🇳🇴 | Brønnøysund (BRREG) | Exact | Exact | **API + bulk** | Cleanest in the region |
| Denmark 🇩🇰 | CVR / Virk | Exact | Exact | **API + bulk** | Mandatory årsrapport, bulk-downloadable |
| Sweden 🇸🇪 | Bolagsverket | iXBRL parsing | iXBRL parsing | **API only**, rate-limited | iXBRL mandatory since 2024, coverage growing |
| Finland 🇫🇮 | PRH + Stat.fi | ❌ Only ~10k via iXBRL | ❌ €20k for banded | **API + bulk** (registry) / **API only** (XBRL) | See dedicated section below |
| Latvia 🇱🇻 | Uzņēmumu reģistrs | Patchy | Patchy | **Bulk download** (CSV/Excel) + Lursoft (paid) | Annual reports filed but bulk extract is hard |
| Lithuania 🇱🇹 | Registrų centras + Sodra | Annual statements (since 2004) | **Sodra: monthly per-company headcount + avg salary, free** | **Bulk download** (open data dumps) | Best free headcount of all 7 |
| Poland 🇵🇱 | KRS / eKRS | Exact, free XML financials since 2019 | Patchy | **API + per-company XML download** | Headcount not consistent in KRS |

## Finland — detailed (the hard one)

### Free official sources

**Both API and bulk download are available** — unlike Estonia (CSV/JSON dumps only), Finland's PRH offers both per-company REST lookups and a bulk ZIP dump of the whole registry. Choose per use case: API for live searches and incremental updates, ZIP for a one-shot full-database seed.

**PRH YTJ Open Data API** — `https://avoindata.prh.fi/opendata-ytj-api/v3`

REST + JSON, no auth, daily updates. ~817k registered companies.

Endpoints:
- `GET /companies` — **search API**: by name, location, businessId, companyForm, mainBusinessLine (TOL 2008), postCode, registration date, paginated
- `GET /all_companies` — **bulk ZIP download** of the entire registry
- `GET /description`, `GET /post_codes` — code lookups

Per-company fields: business ID, all names (current + previous + parallel + auxiliary), addresses, company form, main business line (TOL 2008 code + descriptions FI/SV/EN), website, registration dates, trade-register status.

**Does NOT include revenue or employee count.**

**PRH XBRL Open Data API** — `https://avoindata.prh.fi/opendata-xbrl-api/v3`

REST API only (no bulk dump for financials — you have to walk the listing endpoints and fetch one filing at a time). Endpoints: `/financials`, `/all_financials`, `/all_financial_statements`, `/financial`. The first three return JSON metadata; `/financial` returns the raw iXBRL XML for a single filing.

Coverage problem (empirically verified by sampling 2026-05):
- Total iXBRL filings ever in API: ~57k
- Filings for FY 2024-12-31: ~10k
- Filings for FY 2022-12-31: ~6k (growing year-over-year)
- ~10–15k unique companies have ever filed iXBRL, vs **~300k active** limited companies in Finland

iXBRL filing has been **optional since 2021**. Most small Oy still file PDFs, which are not in this API at all.

Format problem: the OYTP taxonomy uses opaque codes (`fi_met:mi53`, `fi_met:md103`) that map to Finnish concepts via a label file published by State Treasury (Valtiokonttori). Decoding requires fetching and parsing the labels XML. Doable, just not free in time.

**Headcount in iXBRL:** the OYTP taxonomy includes a "personnel average during period" concept, but disclosure is only required for medium/large companies under Finnish accounting law. Realistic available-headcount set is even smaller than 10k.

### Paid official source — Statistics Finland Business Register

`https://stat.fi/en/services/order-statistical-data/data-extractions-from-the-business-register/price-list`

One-off extracts, tiered:

| Records | Price |
|---|---|
| 0–249 | €300 |
| 1,000–1,499 | €800 |
| 500,000+ | €10,100 |

Multipliers: ×2.0 business use, ×1.5–3.0 multiple deliveries/year, +25.5% VAT, +€115/hr custom work, −20% for 3-year contract.

Realistic full-country business-use cost: **~€20k one-off, ~€30–40k/yr with quarterly refresh**.

Built from administrative sources (Tax Administration: VAT returns + employer register/payroll), so coverage is essentially every active company. **But:**

1. **Banded, not exact.** Personnel as size class (0, 1–4, 5–9, 10–19, 20–49, 50–99, 100–249, 250–499, 500–999, 1000+). Turnover similarly banded.
2. **Annual cadence.** 12–18 month lag.
3. **Legitimate zeros.** Holding companies, dormant Oys, pre-revenue startups truthfully have 0/0.

### Paid private sources

- **Vainu** — €3,500/yr (Prospecting), €9,900/yr (Nordic Business), €12,000/yr (Global). Exact numbers, normal API. Pulls from PRH + enrichment.
- **Asiakastieto (Enento)** — no public pricing, contact sales. Per-call API model. Returns `personnel` and `turnover` per company. Heavyweight, finance-grade.

### Cheap/free workarounds for Finland

Ranked by practical viability:

1. **iXBRL parser** (free, exact, ~10k coverage). Map the `fi_met:*` codes once via the OYTP label file. Best quality data for the largest, most-searched companies.
2. **Public Finnish business directories** — finder.fi, kauppalehti.fi/yritykset, taloussanomat.fi/yritys display banded headcount/turnover on public pages, free, no login. Same data Stat.fi sells. Scraping is ToS-grey but technically simple.
3. **Verohallinto public corporate tax data** — Finnish Tax Administration publishes annual public corporate tax records (taxable income, tax paid). CSV released each November. Backsolve revenue from taxable income with sector multiplier. No headcount.
4. **Eurostat SBS (Structural Business Statistics)** — aggregate medians per NACE × country. Useful as imputation: "company X is in NACE 62.01 in FI → typical such company has 4 employees, €350k turnover." Per-company baseline for all 300k.
5. **LinkedIn employee bands** — public, ToS-violating, rate-limited. Skip unless desperate.

### Recommended Finland tiering

Free/cheap layered approach:

- **Tier A (~10k):** iXBRL → exact turnover + personnel. Label "From annual filing".
- **Tier B (~50k):** Verohallinto tax CSV → revenue estimate. Label "Estimated from tax records".
- **Tier C (rest):** NACE-based Eurostat median. Label "Industry estimate".

Total cost: zero, plus a few days of parser work. Coverage 100% with quality clearly labelled.

If/when revenue allows, upgrade Tier C to Asiakastieto (per-call pricing scales with usage) or Vainu €9,900/yr.

## Norway — BRREG

`https://www.brreg.no/en/use-of-data-from-the-bronnoysund-register-centre/datasets-and-api/`

API-first. Free, no auth, NLOD licence. Returns full annual accounts: revenue, EBITDA, operating result, net result, total assets, equity, debt, plus employee count. Single-lookup, complex search, and bulk dataset download all supported. **The reference implementation we should build first.**

## Denmark — CVR / Virk

`https://datacvr.virk.dk/data/?language=en-gb`

Free REST API, JSON, no auth for basic lookups. Annual reports (årsrapporter) mandatory for all limited companies, machine-readable, free download from mid-1990s onward. Headcount included for companies above the small-company threshold.

## Sweden — Bolagsverket

`https://bolagsverket.se/en/sokforetagsinformation/omsokforetagsinformation.3045.html`

Free API with rate limits. Basic data (name, org number, legal form, address, SNI codes, registration date) is straightforward. Revenue/headcount comes from annual reports — **iXBRL mandatory since 2024**, so coverage is improving rapidly. Today still patchy; in 2–3 years should match Norway/Denmark.

## Latvia — Uzņēmumu reģistrs

`https://www.ur.gov.lv/en/get-information/`

Free CSV/Excel of basic registry data. Annual reports filed but ergonomically hard to bulk-extract — Lursoft monetises this gap. No clean API like BRREG. Expect partial coverage and per-company scraping for financials.

## Lithuania — Registrų centras + Sodra

`https://www.registrucentras.lt/jar/index_en.php`

Two-source country:

- **Registrų centras** — basic registry, public search free. Annual financial statements mandatory since 2004, available but extraction effort similar to Latvia.
- **Sodra** (state social insurance) — publishes monthly open dataset with **per-company employee count and average salary**. Mandatory employer reporting, near-100% coverage of employers. Best free headcount source of any country in our list.

## Poland — KRS / eKRS

`https://www.biznes.gov.pl/en`

REST API for KRS basics. Annual financial statements as XML, free download from eKRS (`ekrs.ms.gov.pl`), mandatory since 2019. Available data: full P&L, balance sheet, cash flow, audit info. PKD industry codes.

Headcount inconsistent — present in some annual statements but not reliably across the register. May need supplementing.

## Architecture implications

The current `Colt.Resources.Company` schema (market enum, `(registry_code, market)` identity, integer `employees_latest`, decimal `revenue_latest`, NACE-prefix industry filter) handles all 7 countries' **exact-number** sources cleanly. Adding a country = new `Colt.Services.Ingest.{Country}.{Source}` subtree following the EE/RIK pattern.

Schema changes needed:
- Broaden `AnnualReport.source` enum beyond `[:rik]` before adding country #2.
- Add `:pl` to `Company.market` enum.

Schema changes deferred until Finland tier C/B lands:
- `is_estimated :boolean` or `confidence :atom` on `AnnualReport` (for NACE-median imputation and tax-derived estimates).
- Banded fields if we ever buy Stat.fi (or coerce bands to midpoints — pragmatic, common in B2B tools).

Recommended build order (by data-quality cliff, not geography):
1. Norway (cleanest, reference implementation)
2. Denmark (similar shape, validates pattern)
3. Poland (XML parsing, exercises parser layer)
4. Lithuania (two-source merge per country)
5. Sweden (iXBRL-heavy)
6. Latvia (partial coverage)
7. Finland (tiered estimation, hardest)

## Sources

- [PRH open data portal](https://avoindata.prh.fi/en)
- [PRH YTJ API schema](https://avoindata.prh.fi/opendata-ytj-api/v3/schema?lang=en)
- [PRH XBRL API schema](https://avoindata.prh.fi/opendata-xbrl-api/v3/schema?lang=en)
- [Statistics Finland Business Register](https://stat.fi/tup/yritysrekisteri/index_en.html)
- [Stat.fi price list](https://stat.fi/en/services/order-statistical-data/data-extractions-from-the-business-register/price-list)
- [Vainu pricing](https://www.vainu.com/pricing)
- [Asiakastieto Company Basics API](https://www.asiakastieto.fi/web/en/frontpage/integrations/company-basics-api.html)
- [Verohallinto public tax data](https://www.vero.fi/en/individuals/tax-cards-and-tax-returns/income-and-deductions/public_tax_information/)
- [Eurostat SBS](https://ec.europa.eu/eurostat/web/structural-business-statistics)
- [BRREG](https://www.brreg.no/en/use-of-data-from-the-bronnoysund-register-centre/datasets-and-api/)
- [CVR/Virk](https://datacvr.virk.dk/data/?language=en-gb)
- [Bolagsverket](https://bolagsverket.se/en/sokforetagsinformation/omsokforetagsinformation.3045.html)
- [Latvia UR](https://www.ur.gov.lv/en/get-information/)
- [Registrų centras](https://www.registrucentras.lt/jar/index_en.php)
- [Poland KRS](https://www.biznes.gov.pl/en)
