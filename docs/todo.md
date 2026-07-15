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

## Filters — EMTAK / industry picker

- **EMTAK code search is bad — make it a tree + search picker.** The current
  industry picker (`ColtWeb.Campaigns.FiltersLive`, `industry_search` event →
  `Colt.Filters.IndustryLabels.search/1`) is search-only: a flat box that returns
  matching labels with no way to browse the hierarchy. It should be a separate
  stage / popup that is **both tree-browsable and searchable**, in the familiar
  language (Estonian EMTAK terms, not raw codes). 1Contact Eesti does this well —
  use it as the reference. EMTAK is hierarchical (section → division → group →
  class → 5-digit code); the picker should let you drill down the tree as well as
  type to filter.

## Contact acquisition — owner names (step 2)

- **Import registry person names (board/owner) so we can guess + verify owner
  emails.** See `docs/specs/contact-acquisition.md` §3/§5. The owner rung shipped
  with **step 1 only**: use `Company.registry_email` when the AI classifies it as a
  personal address. Step 2 — take the owner's *name*, construct `first@domain` and
  `first.last@domain`, verify, use the one that passes — is **not built**, because
  we import no person names at all.

  To build: RIK's personnel/representation dump is **not** among the three file
  families `lib/colt/services/ingest/ee/rik/download.ex:17-36` fetches, and nothing
  under `ingest/ee/rik/` touches `Colt.Resources.Person` (grep for
  `isik|juhatus|esindus|eesnimi|perenimi` returns only company-`nimi` hits). So:
  **first verify the personnel dump actually exists on avaandmed.ariregister.rik.ee
  and what it contains** — don't assume from the spec table. Then add it to the
  download list, add a parser → `Person` with a registry source + role, and add the
  candidate-generator/verifier resolver.

  Scope check before investing: this only helps the **company-domain minority**.
  66% of EE registry emails are on free domains (gmail/mail.ru/hot.ee) where there
  is no company domain to guess against, so step 2 is inapplicable to two-thirds of
  the market. Step 1 already covers those.

  Same mechanism generalises to FI/LV/LT/NO/DK (all publish names free) — one
  parser per market, prioritised by client demand.

## Company categories

- **Company has many categories. Support them, import them.** I know Rik does at
  least. First do this just for Rik, then we can look further.

## Redesign

- **The marketing/product UI needs a redesign.** Current inspiration:
  - **loops.so** — simplicity. Pare back, fewer controls, calm surfaces.
  - **outfunnel.com** — clarity. The hero animation gives instant recognition of
    what the product does; aim for that immediate "I get it" moment.
  - **maildoso.ai** — its promises / value-prop framing. Borrow how they state
    what you get.
