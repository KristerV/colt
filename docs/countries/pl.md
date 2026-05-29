# Poland — KRS / eKRS

**Status: BLOCKED on revenue + employees.** Phase A halted per the
`docs/data-sources.md` stop-clause "if revenue+employees gated behind
login/payment, write the plan doc, no code". The Polish situation is
adjacent: data is technically free per-company through a browser, but
there is **no free programmatic bulk path**. Building an ingest today
means either scraping a bot-protected UI at ~500k req scale or paying a
third-party reseller. Both are out of scope.

This document records the probe, why we stopped, and what would unblock
us later.

---

## Sources probed (2026-05-28)

### 1. KRS REST API — `https://api-krs.ms.gov.pl`

Free, no auth, JSON.

```
GET https://api-krs.ms.gov.pl/api/Krs/OdpisAktualny/{krs_number}?rejestr=P&format=json
```

`rejestr=P` = Register of Entrepreneurs (limited companies, partnerships,
co-ops). `rejestr=S` = associations.

Verified live with `0000635012` (Allegro Sp. z o.o.) → HTTP 200, 20 KB JSON.

Fields returned (relevant subset):

| JSON path                                                                 | Meaning                                |
| ------------------------------------------------------------------------- | -------------------------------------- |
| `odpis.dane.dzial1.danePodmiotu.nazwa`                                    | Legal name                             |
| `odpis.dane.dzial1.danePodmiotu.formaPrawna`                              | Legal form (SP. Z O.O., S.A., …)       |
| `odpis.dane.dzial1.danePodmiotu.identyfikatory.regon` / `.nip`            | REGON 9/14-digit, NIP 10-digit         |
| `odpis.dane.dzial1.siedzibaIAdres.adres.{ulica,nrDomu,kodPocztowy,…}`     | Address                                |
| `odpis.dane.dzial3.przedmiotDzialalnosci.przedmiotPrzewazajacejDzialalnosci[].{kodDzial,kodKlasa,kodPodklasa,opis}` | PKD 2007 main activity |
| `odpis.dane.dzial3.wzmiankiOZlozonychDokumentach.wzmiankaOZlozeniuRocznegoSprawozdaniaFinansowego[].zaOkresOdDo` | List of years a financial statement was filed (metadata only — no figures) |

**KRS API does NOT include:**
- Revenue
- Employee count
- Website, email
- Industry beyond PKD codes

**Bulk:** none. To enumerate the register we'd iterate
`0000000001..~0001200000` (sparse — many slots return HTTP 204).
Coarse estimate: ~700k–900k active REJP entities; ~1.0–1.2M slots ever
issued. At 100 ms/request with conservative concurrency (no documented
rate limit, but Ministry portals throttle aggressive clients) full sweep
is **~20–30 hours**. Re-running daily for changes is feasible.

**Licence:** Free public-information regime under the KRS Act
(art. 8a ustawy o KRS). No published terms-of-use restrict reuse.

### 2. eKRS RDF — Repository of Financial Documents

`https://ekrs.ms.gov.pl/rdf/pd/search_df` (redirects to
`https://rdf-przegladarka.ms.gov.pl/`).

This is the only **free** source of revenue + headcount for Polish
companies. Annual financial statements have been mandatory in
structured XML since October 2018; this is where they live.

Findings:

- **Free, no auth, per-company.** Enter a KRS number, get a list of
  filings, download each as XML (e-Sprawozdanie Finansowe schema by the
  Ministry of Finance) + XAdES signature.
- **No public API.** Confirmed by `mojeanalizy.pl`, MGBI, Transparent
  Data: "the eKRS financial document viewer operated by the Ministry of
  Justice of Poland does not have an API. There is no free way to
  quickly download large volumes of reports."
- **Anti-bot protection.** The browser is fronted by Imperva Incapsula
  (verified: root document references `/_Incapsula_Resource?…` script).
  Programmatic enumeration would have to defeat bot challenges.
  Scraping at ~500k-company scale is both technically expensive and ToS
  grey.

### 3. REGON BIR1 API — `api.stat.gov.pl`

Free, but **requires API key** (apply via email to `regon_bir@stat.gov.pl`).

Returns: identification (REGON, NIP, KRS), addresses, PKD codes,
forma prawna, registration/deregistration dates. **No revenue, no
employees.** Useful as a complement to KRS for ID resolution; not a
substitute for RDF financials.

Per CLAUDE.md credential rules this would be a per-user / env key with
`raise in prod, :missing_api_key in dev`.

### 4. dane.gov.pl — Polish national open data portal

Searched for `krs`, `sprawozdania finansowe`. No company-level annual
financials dataset. The hits are ZUS / FUS pension-fund accounts,
nothing applicable to private companies.

### 5. Paid third parties (for context — not in scope)

- **Transparent Data** — REST API over the same eKRS XMLs. Per-call
  pricing.
- **MGBI** — `pl-krs-rdf-record` API model. Per-record pricing.
- **Vainu** — Nordic-focused, may cover PL via their EU bundle.

These are the only realistic bulk paths today.

---

## Data structure (for the day this unblocks)

E-Sprawozdanie Finansowe XML schema (Ministry of Finance, namespaced
under `http://crd.gov.pl/wzor/2018/.../`) has variants per entity type;
the "Jednostka inna" (other entity) variant is the common one for
limited companies. Relevant nodes:

| XPath (approximate)                                                                                                  | Meaning                                                       |
| -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `//Naglowek/dataOd`, `//Naglowek/dataDo`                                                                              | Fiscal year start / end                                       |
| `//Naglowek/jezykSprawozdania`                                                                                        | Statement language (PL, sometimes EN)                         |
| `//Wprowadzenie/...`                                                                                                  | Narrative intro, basis of preparation                         |
| `//RachunekZyskowIStrat/...` (P&L)                                                                                    | Income statement                                              |
| `//RachunekZyskowIStrat/PrzychodyNetto[ZeSprzedazyIZrownaneZNimi]` (variant A) **or** `…/PrzychodyNetto[ZeSprzedazy]` (variant B) | **Net revenue from sales (PLN)** — the revenue field we want |
| `//Bilans/...`                                                                                                        | Balance sheet                                                 |
| `//DodatkoweInformacjeIObjasnienia/...`                                                                               | Notes; sometimes contains avg headcount                       |
| `//InformacjaDodatkowa/...//przecietneZatrudnienieWRokuObrotowym` (location varies) | **Average employees in fiscal year** — disclosure not always present |

Units: **PLN**, integers (zlotys), sometimes thousands. Verify
`jednostkaMiary` / `wPelnychZlotych` flag per filing.

Revenue coverage if we ever ingest: ~100% for spółki obowiązane (all
KRS-registered limited companies post-2018). Headcount coverage:
**inconsistent** — `data-sources.md` already calls this out. Realistic
expectation: 50–70% of filings include `przecietneZatrudnienie`, lower
for small `mikro`/`mały` schedules. We should label confidence per-row.

FX: store EUR with a documented module-attribute rate, same pattern as
EE. Suggested attribute: `@pln_to_eur 0.234` (ECB ref ~4.27 PLN/EUR
2026-05). Flag with `is_estimated: true` or carry both `revenue_native`
+ `revenue_eur` if/when the schema gains those fields.

---

## What it would take to unblock

In order of preference:

1. **Wait for an official RDF API.** PARP and the Ministry of Justice
   have been publicly discussing exposing one since the 2026 RDF
   relaunch. If it lands, the work is straightforward (one-shot per-KRS
   XML fetch, same shape as Norway/Denmark).
2. **Budget for Transparent Data or MGBI.** Per-call pricing
   plausibly fits if we cap revenue ingest to ICP-matched companies
   (10–50k of the 700k) rather than the full register. Quote needed.
3. **Negotiated bulk extract from Ministry of Justice.** Public-data
   FOI route. Slow, but free.

Scraping the RDF browser is not recommended — Incapsula plus the ToS of
prs.ms.gov.pl make this a maintenance and legal liability we shouldn't
take on.

---

## Pipeline stages (planned, NOT BUILT)

Mapped to EE/RIK, for whenever we unblock:

| Stage    | EE/RIK module                | PL equivalent (planned)                                |
| -------- | ---------------------------- | ------------------------------------------------------ |
| 1        | `Download`                   | `Pl.Ekrs.RegistrySweep` — iterate KRS numbers via API |
| 2        | `CompaniesImport`            | `Pl.Ekrs.CompaniesImport` — upsert from JSON          |
| 3        | `CompanyDetails`             | (skipped — no website/email source in KRS)            |
| 4        | `AnnualReports`              | `Pl.Ekrs.AnnualReports` — XML parser per KRS, **blocked** |
| 5        | `GrowthRollup`               | `Pl.Ekrs.GrowthRollup` — reuse pattern verbatim       |

Stages 1–2 (KRS basics only) are buildable today and would give us
company identity + PKD + address for ~700–900k Polish limited
companies. Without stage 4 we can't deliver revenue/employees and the
data is downstream-useless for the prospecting filters that depend on
`revenue_latest` and `employees_latest`. Hence ❌ on full ingest.

If we ever decide that company-identity-only PL is worth shipping (for
manual enrichment workflows, ICP coverage signalling, etc.), the
`AnnualReport.source` enum stays at `:ekrs` and stages 1–2 can land
independently. Note for the user: **this is a product call, not a tech
one.**

---

## For the user

- **Oban cron line:** none added — no worker exists.
- **Enum delta:** `AnnualReport.source` already includes `:ekrs` and
  `Company.market` already includes `:pl`. No schema work to undo.
- **Module attribute placeholder for PLN→EUR:** `@pln_to_eur 0.234`
  (ECB ref ~4.27 PLN/EUR as of 2026-05). Will need a refresh whenever
  this unblocks.
- **Decision needed:** approve one of (1) wait for official API,
  (2) budget for Transparent Data / MGBI, (3) ship KRS-basics-only PL
  ingest (no revenue/employees). Default recommendation: **wait**.

## Sources

- [api-krs.ms.gov.pl — KRS REST API](https://api-krs.ms.gov.pl/api/Krs/OdpisAktualny/0000635012?rejestr=P&format=json)
- [eKRS RDF browser](https://ekrs.ms.gov.pl/rdf/pd/search_df)
- [PARP report on registry data reuse (PDF)](https://www.parp.gov.pl/storage/publications/pdf/Mozliwosci-wykorzystania-danych-rejestrowych_FINAL.pdf)
- [mojeanalizy.pl — reading Polish XML financial statements](https://mojeanalizy.pl/en/teksty/jak-odczytac-e-sprawozdanie-finansowe-xml)
- [GUS REGON BIR1 API](https://api.stat.gov.pl/Home/RegonApi?lang=en)
- [Ministry of Justice — RDF info page](https://www.gov.pl/web/sprawiedliwosc/przegladarka-dokumentow-finansowych)
- [Transparent Data — paid eKRS API](https://transparentdata.pl/en/api-company-information-poland/financial-report)
- [MGBI — paid eKRS API](https://www.mgbi.pl/poradniki/jak-pobrac-przez-api-wybrane-pola-sprawozdania-finansowego-podmiotu-z-krs/)
