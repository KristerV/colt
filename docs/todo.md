# TODO — deferred from earlier phases

Things noted while building later phases that should be picked up later. Not
blocking the phase that surfaced them.

## Filters

- **Company age min/max slider** (spec §5.4, design view-3 `Founded` fset). Not a
  year picker — a min/max age range slider (e.g. "company is 2–10 years old").
  The `Company` resource has no `founded_at` / registered-at field and the rik.ee
  Phase 1 ingest doesn't populate one. To build: add a `founded_at` (or
  `registered_at`) date attribute to `Colt.Resources.Company`, populate it from
  the rik.ee `ettevotja_rekvisiidid` CSV (the registry tracks an
  `esmane_kanne_kpv` / first-entry date), backfill with a one-shot migration over
  existing rows, derive age from it, then add a min/max age range filter + `Fset`
  to `ColtWeb.Campaigns.FiltersLive`.

- **VAT-registered signal** (design view-3 Signals fset). No VAT field exists on
  `Company` and rik.ee Avaandmed doesn't expose KMKR (VAT) status in the basic
  open-data dump. To restore: either source from EMTA's VAT lookup (separate
  endpoint, rate-limited) or scrape teatmik.ee. Whichever, add a
  `vat_registered :boolean` attribute, an ingest path, and the checkbox.

## Company categories

- **Company has many categories. Support them, import them.** I know Rik does at
  least. First do this just for Rik, then we can look further.
