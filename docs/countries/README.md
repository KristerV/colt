# Per-country ingest status

Single source of truth for what's shipped, what's running, and what's blocked.
Per-country detail lives in the matching `<cc>.md` file in this directory.

The build target for every country is the same: populate
`Colt.Resources.Company` (registry identity) and `Colt.Resources.AnnualReport`
(revenue + employees per fiscal year) for the full company universe, using
only **free** sources.

## At a glance

| Code | Country  | Source(s)                       | Ingest code | Cron in prod          | Verified in dev | UI live? | Notes |
|------|----------|---------------------------------|-------------|-----------------------|-----------------|----------|-------|
| EE   | Estonia  | RIK Avaandmed                   | ✅ shipped  | `EeIngest`            | ✅ full         | ✅       | Reference implementation. Full population. |
| FI   | Finland  | PRH YTJ + XBRL                  | ✅ shipped  | `FiIngest`            | ✅ partial      | ✅       | iXBRL coverage limited to ~10k filings; rest of FY register is identity-only. |
| LV   | Latvia   | UR open data                    | ✅ shipped  | `LvIngest`            | ✅ slice        | ✅       | Verified with ELKO, LMT, ATTA-1. Industry codes NULL — `industry_code` gap. |
| LT   | Lithuania| Registrų centras + Sodra        | ⚠️ partial  | `LtIngest`, `LtHeadcountIngest` | ✅ RC slice / ❌ Sodra | ✅ | RC pipeline verified. Sodra (employees) blocked by Cloudflare — three bypass options in `lt.md`. |
| DK   | Denmark  | CVR / Virk XBRL                 | ✅ shipped  | `DkIngest`            | ✅ slice (1000) | ✅       | Verified with Q8 Danmark, Terma. Revenue ~15% (Class B SMEs legally hide); employees ~94%. `industry_code` gated behind 3-week-approval CVR auth. |
| NO   | Norway   | BRREG (enheter + regnskap)      | ✅ shipped  | `NoIngest`            | ⏳ in progress  | ❌       | First slice run kicked off this session. Flip UI to `:live` after the run lands rows. |
| SE   | Sweden   | Bolagsverket HVD                | ✅ shipped  | `SeIngest`            | ❌ blocked      | ❌       | Requires OAuth2 client creds (free but human-issued by Bolagsverket — form-gated). Fails fast with `:missing_api_key` until creds arrive. |
| PL   | Poland   | KRS / eKRS                      | ❌ none     | none                  | ❌              | ❌       | KRS API has no revenue/employees; eKRS bulk is Incapsula-protected; only paid resellers. Plan doc only. |

## Dev-DB coverage (snapshot — varies per run)

| Market | Companies | Annual reports | …with revenue | …with employees |
|--------|-----------|----------------|---------------|-----------------|
| EE     | 11,190    | 1,163          | 1,163         | 1,163           |
| FI     | 13,872    | 211            | 211           | 153             |
| LV     | 14,466    | 2,051          | 2,051         | 2,051           |
| LT     | 1,150     | 1,655          | 1,442         | 0               |
| DK     | 997       | 833            | 125           | 786             |
| NO     | 0         | 0              | 0             | 0               |
| SE     | 0         | 0              | 0             | 0               |
| PL     | 0         | 0              | 0             | 0               |

EE/FI numbers reflect prior bench-tier prod-style runs. LV/LT/DK reflect this session's slice verifications (LV ran 3% of the dump; LT/DK ran `limit: 1000`). LT's 0 employees column is the Sodra block — RC alone doesn't publish headcount.

## Outstanding problems by country

### LT — Sodra Cloudflare wall
`atvira.sodra.lt` returns the Cloudflare interactive challenge ("Just a moment…") to every non-browser fetcher we tried (curl, curl_cffi Chrome impersonation, cloudscraper, headless chromium with new headless mode). Until one of the following ships, LT companies have **revenue from RC but no employee count**:

1. **CDP through Colt's existing chromium** — preferred (we already run a persistent chromium for scrape; route the CSV fetch through it).
2. **External CF-solving proxy** — fastest to ship, costs $.
3. **Allowlisting via `info@sodra.lt`** — slowest, cleanest, free.

See `lt.md` for the integration shape; the orchestrator already accepts an injectable `:fetcher` callable.

### SE — OAuth2 credentials gate
Bolagsverket's HVD API is free but requires registering a client (name + email + phone form). Issuance is human-mediated, ~few business days. The runtime config and parser are wired; once creds land in `BOLAGSVERKET_CLIENT_ID` / `BOLAGSVERKET_CLIENT_SECRET`, the Oban job runs as-is.

Bulk file path exists (`bolagsverket_bulkfil.zip` + `scb_bulkfil.zip`) but the download page is CAPTCHA-gated, so it's only a fallback if a human can grab the URL after solving the challenge.

### DK — Coverage cliff on revenue
Danish "Class B" small-company filings legally omit revenue (only `GrossProfitLoss` is required). The XBRL we parse honours that — `revenue_eur` is NULL for ~85% of companies, employees populated for ~94%. Revenue-band ICP filters will silently exclude most of the DK universe. Documented; no code fix possible.

### DK — Industry codes
`branchekode` (DK NACE) is only in the auth-gated `cvr-permanent` index. Free path has no industry codes → DK companies get `industry_code = NULL`, NACE-prefix ICP filters no-op for `:dk`. Same shape as LV / LT.

### NO — Employee coverage cliff
`antallAnsatte` is sourced from NAV's AA-registeret, which only covers companies that file employer reports. 86% gap is mostly 1-person AS where the owner takes dividends instead of formal wages. ~60k of 427k AS will have employees. Revenue is fine (~91% of AS file accounts).

### PL — No free path to financials
KRS REST gives identity + PKD codes, no revenue/employees. eKRS annual statements exist as XML per company but the bulk endpoint is Incapsula-protected and there's no public API. The only practical paths are paid (Transparent Data, MGBI) or "wait for the Ministry of Justice's promised public RDF API". Not shipping until one of those resolves.

## Schema gaps shared across countries

- **`industry_code` missing for LV, LT, DK** (and PL, but PL isn't shipping). NACE/EVRK/PKD lives in different open datasets per country, often gated. Liid's NACE-prefix filter will skip these markets until each country's industry-code path is plumbed in.
- **`source` enum stamps only one source per `(company_id, year)` row.** When LT's Sodra ships, its UPSERT will keep `:rc` if revenue exists, otherwise `:sodra` — meaning `source` becomes "whichever filled first", not provenance-complete. If we ever need true multi-source attribution, add a `headcount_source` column.

## Reading order for a new contributor

1. `docs/data-sources.md` — what's available per country, with paid alternatives
2. `docs/large-csv-ingest.md` — the performance playbook (raw SQL `unnest`, stream-by-group, etc.)
3. `lib/colt/services/ingest/ee/rik/*` — reference implementation
4. The `<cc>.md` for the country you're touching
