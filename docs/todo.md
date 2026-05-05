# TODO — deferred from earlier phases

Things noted while building later phases that should be picked up later. Not
blocking the phase that surfaced them.

## From Phase 3 — filters

- **Industry chip coverage at scale.** The panel shows the 12 most common
  EMTAK codes by company count. At 10k seeded rows that's a usable slice; at
  the full ~200k Estonian registry the long tail is unreachable from chips
  alone. Replacement: typeahead / search input over `Colt.Filters.IndustryLabels`
  (615 NACE classes, all human-labelled), with the top-12 still rendered as
  shortcut chips. Don't bump the chip count to 50+ — that's the wrong UX.

- **Region filter.** Removed in v1 — the registry's `region` field is
  free-text, low-signal, and ate too much sidebar real estate. If we ever
  reintroduce it, do it as a typeahead like the industry idea above, not a
  fixed chip set.

- **Signals (Has registered website / VAT registered / Filed annual report).**
  All three removed in v1. The first two were always thin (website is
  enrichment's job, VAT has no source field). Annual-report-recency could be
  useful for "is this company still alive" but we already have the growth
  bucket as a proxy. Reintroduce only if a real workflow needs it.

- **Founded year filter** (spec §5.4, design view-3 `Founded` fset). The `Company`
  resource has no `founded_at` / registered-at field and the rik.ee Phase 1
  ingest doesn't populate one. The Founded fset is omitted from the filter panel
  in v1. To restore: add a `founded_at` (or `registered_at`) date attribute to
  `Colt.Resources.Company`, populate it from the rik.ee `ettevotja_rekvisiidid`
  CSV (the registry tracks an `esmane_kanne_kpv` / first-entry date), backfill
  with a one-shot migration over existing rows, then add a range filter and a
  Founded `Fset` to `ColtWeb.Campaigns.FiltersLive`.

- **VAT-registered signal** (design view-3 Signals fset). No VAT field exists on
  `Company` and rik.ee Avaandmed doesn't expose KMKR (VAT) status in the basic
  open-data dump. To restore: either source from EMTA's VAT lookup (separate
  endpoint, rate-limited) or scrape teatmik.ee. Whichever, add a
  `vat_registered :boolean` attribute, an ingest path, and the checkbox.

## From Phase 4a — enrichment infra

- **GLM 4.7 reasoning forced off for `:cheap`.** GLM 4.7 on OpenRouter is a
  reasoning model: with reasoning enabled it returns `message.content` as a
  list of typed parts (`reasoning.text` + `text`) and burns the token budget
  on chain-of-thought before emitting any answer. Smoke test with
  `max_tokens: 20` came back with `content: nil` while still billing for 20
  reasoning tokens. Workaround in `Colt.Services.Ai.Complete`: pass
  `reasoning: %{effort: "none"}` for `:cheap`, plus a defensive
  `extract_text/1` that handles list-of-parts. Revisit if any `:cheap`
  callsite (SummarizeCompany, PickContactPages, GoogleSearch result-pick,
  batched title-match) actually benefits from reasoning — in that case let
  the caller opt back in via an option, don't flip the global default. Also
  worth re-checking after model swaps: the `:cheap`/`:smart` aliases hide
  the underlying provider, and the reasoning toggle is provider-specific.

## From Phase 5 — funnel

- **Route campaigns to the right view by status.** Today the Recent sidebar on
  `/campaigns/new` always links to whatever the row's last URL was, and the
  wizard views (`/icp`, `/market`, `/filters`) don't redirect when the
  campaign has already moved past them. The visible failure: clicking Confirm
  on `/campaigns/:id/filters` for an already-`:enriching` campaign re-runs
  `Services.Enrichment.Start.run/3`, which tries to bulk-create
  `CampaignCompany` rows that already exist and crashes with
  `campaign_companies_campaign_company_index` "has already been taken".

  Fix in two places:
    1. **Recent sidebar (NewLive)** — route by `campaign.status`:
       - `:draft` + no `icp_description` → `/campaigns/:id/icp`
       - `:draft` + `icp_description` set → `/campaigns/:id/market`
       - `:collecting` (market set, filters not finalized) → `/campaigns/:id/filters`
       - `:enriching | :complete | :archived` → `/campaigns/:id/funnel`
    2. **Defensive redirects in IcpLive / MarketLive / FiltersLive** —
       on mount, if the campaign's status is past this view, `push_navigate`
       to the right one (probably funnel for anything `>= :enriching`).
       Closes the deep-link footgun.

  Spec §5.1 already prescribes the sidebar behaviour ("Clicking a row
  navigates to that campaign's view 4"); the wizard-redirect part is implied
  by §5.5 "Read-only: no edits to filters or ICP after this view".

## From other phases

(Add as you go — keep the format above: what, why deferred, what it would take
to bring back.)
