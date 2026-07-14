# Industry codes: the NACE Rev. 2.1 playbook

Read this **before** wiring `industry_code` for a new country. It exists because
getting this wrong is silent: the ingest succeeds, the rows look fine, and the
industry filter just quietly returns the wrong number of companies. That is
exactly how ~36% of Norway's 1.1M companies sat unreachable for months, and why
picking "car repair" in the UI returned zero.

## The one thing to know

**The EU renumbered NACE on 2025-01-01.** NACE Rev. 2 (2008) → **NACE Rev. 2.1**.
This is not cosmetic:

- Division **45 no longer exists**. Motor-vehicle repair moved to `95.31`;
  vehicle sales moved into `46`/`47`.
- `62.01`/`62.02`/`62.09` → `62.10`/`62.20`/`62.90`. `41.10`/`41.20` → `41.00`
  (and `41.10` actually lands in `68.12`, a different section).
- There are **22 sections (A–V)**, up from 21. Section membership changed —
  division 95 is under `T` now, not `S`.
- 159 of 615 Rev. 2 classes (26%) fan out to multiple Rev. 2.1 classes.
- **23 codes were reused for an unrelated activity.** `4781` is a market food
  stall in Rev. 2 and a car dealership in Rev. 2.1. A bare `4781` with no
  revision attached is genuinely undecidable.

Zero Rev. 2 classes disappear without a successor, so no company is stranded —
but the mapping is *total, not deterministic*.

## What Liid does

`companies.industry_code` holds **NACE Rev. 2.1 only**. Legacy codes are
forward-translated **at import** by `Colt.Filters.NaceMigration`, never by a
backfill migration. That matters: registries keep serving old codes, so a one-off
backfill would be undone by the next ingest. Translating on the way in means
re-running any ingest job self-heals, and the mapping decays to a no-op as
registries migrate.

`Colt.Filters.IndustryLabels` — the vocabulary the campaign filter UI offers — is
generated from the Rev. 2.1 structure. If the data and the labels disagree on
revision, the filter matches nothing and nobody notices.

## Rule 1: never normalize backwards

The tempting shortcut is "take each company's newest Rev-2 code and skip the
mapping work." **Don't.** Rev 2.1 is where every registry is heading, and the data
is already mostly there:

| Market | Rev 2.1 share | Classifier version in source? |
|--------|---------------|-------------------------------|
| NO | 100% | n/a — nothing to translate |
| FI | 99.96% | n/a |
| EE | ~71% | ✅ `emtak_versioon` |
| LT | ~97% | ❌ none |

Importing into Rev. 2 adds rows to the dying vocabulary and buys a bigger
migration later.

## Rule 2: find out whether the source tells you the revision

This is the single highest-value question, and it decides everything downstream.

**If yes** (Estonia's model — `lib/colt/services/ingest/ee/rik/company_details.ex`):
RIK tags every declared activity with `emtak_versioon` (`2` = EMTAK 2008 = NACE
Rev. 2, `3` = EMTAK 2025 = Rev. 2.1). Translate only the version-2 rows via
`NaceMigration.emtak_2008_to_2025/1`. You get exact revision knowledge, the 23
collisions stop being ambiguous, and ~92% of legacy rows translate.

**If no** (Lithuania's model — `lib/colt/services/ingest/lt/sodra/import.ex`):
use `NaceMigration.nace_rev2_to_rev21/1`. It rewrites classes Rev. 2.1 deleted,
leaves classes valid in both alone, and returns `nil` for the 23 collisions —
those companies lose their code rather than get mislabelled. Write the `nil`
**through** to the column; don't skip the row, or a stale code never heals.

> Do not conclude "no version field" from a fixture. The EE fixture was
> hand-authored and omitted `emtak_versioon` *and* `nace_kood` — both of which
> RIK has published all along. Download a real record and look at it.

## Rule 3: verify the code shape, not just its presence

`Company.filtered` matches on `LEFT(industry_code, 4)`. Whatever you store, its
first four characters must be the NACE class:

- **De-dot.** BRREG serves `"43.210"`; `LEFT(_, 4)` on that is `"43.2"` — wrong.
  See `de_dot/1` in the NO importer.
- **5-digit national codes are fine and preferred** — the 5th digit is a national
  subclass that doesn't change the wording. EE stores 5-digit EMTAK; its first 4
  chars are always exactly the published `nace_kood` (verified across all 414,821
  activity records).
- **Watch for group-level declarations.** ~470 EE companies declare at 2–3 digit
  level; those will never match a 4-digit filter. Known, small, accepted.
- ⚠️ **SE is unverified on this axis.** `pick_sni/1` copies the SNI code verbatim
  with no de-dot. If Bolagsverket emits `"43.210"`-style codes, every SE row will
  silently fail every industry filter. Check this when SE creds land.

## Rule 4: prove it with data before you believe it

Don't reason about which revision a feed is on — measure. Partition the source's
codes against the correspondence table:

```
priv/nace/nace_rev2_to_rev21.csv   # Eurostat CorresTab v1.05, 4-digit classes
priv/nace/emtak_2008_to_2025.csv   # RIK üleminekutabel, EMTAK 2008 -> 2025
```

Build three sets — codes only valid in Rev 2, only in Rev 2.1, and in both — then
count your rows against them. A feed with **zero Rev-2-only codes** is fully
migrated (Norway). A feed with both is mixed (Estonia, Lithuania). This is a
few minutes of work and it is the difference between knowing and guessing.

A useful smell test on the market itself: query the registry's own API for a
`45.*` code. If it returns 0 while `43.*` returns thousands, the country is on
Rev. 2.1.

## Gotchas that cost real time

- **The correspondence tables list *any* overlap, however marginal.** EMTAK
  `96099` ("muu teenindus") names `23159` (glass manufacturing) as a target.
  Never blindly take the first row. `gen_nace_migration.exs` documents the
  resolution rules; the useful one is **the identity rule**: if the source's own
  class is among its targets, the class survived and staying put is correct.
  Rules 1+2 resolve 74.7% with no judgement at all.
- **RIK's `/est/api/corresp_table_autocomplete` JSON endpoint is a trap.** It's
  `DISTINCT ON (source)` server-side, so it silently returns only the first
  target per source — 1751 rows where the CSV has 2908, collapsing every 1:many.
  Fine for autocomplete, wrong for translation. Use the CSV.
- **Some classes are unguessable.** EMTAK `47911` fans to 44 targets, `82991` to
  24. Rev. 2.1 restructured retail by product, and the old code carries no
  information about which. We drop these (`nil`) rather than fabricate. That's
  ~7.9% of Estonia's legacy rows, and they heal when the company re-declares.
- **Sections are not stable across revisions.** Anything keying on "45 = motor
  trade" or `~r/^[A-U]$/` breaks. Derive sections from the data.

## Adding a country: the checklist

1. Find the industry field in the **real** source payload (not a fixture). Note
   whether it carries a classifier version or a code-assignment date.
2. Verify `LEFT(code, 4)` is the NACE class — de-dot if needed.
3. Partition the feed's codes (Rule 4). Record the Rev 2.1 share in `README.md`.
4. Wire translation:
   - version available → the EE pattern.
   - no version → `NaceMigration.nace_rev2_to_rev21/1`, write `nil` through.
   - already 100% Rev 2.1 → nothing to do (NO, FI).
5. Add a test asserting a Rev-2 code translates, a Rev-2.1 code passes through,
   and an ambiguous one drops. See `test/colt/filters/nace_migration_test.exs`
   and the EMTAK cases in `test/colt/services/ingest/ee/rik_test.exs`.
6. Sanity-check end-to-end: pick `9531` in the filter for your market and confirm
   the count is non-zero and plausible. Zero means you got the revision wrong.

## Regenerating

Both tables are vendored under `priv/nace/` (~200K) because RIK's download needs
a `__Host-ariregweb` session cookie and a documented curl would rot.

```
mix run priv/scripts/gen_nace_migration.exs   # -> lib/colt/filters/nace_migration.ex
mix run priv/scripts/gen_industry_labels.exs  # -> lib/colt/filters/industry_labels.ex
```

Both files are **generated — never hand-edit them**. Add to the generator. (The
label generator was previously stale and would have silently deleted the module's
hand-written section/tree API; it now emits the whole module and formats its own
output. Keep it that way.)
