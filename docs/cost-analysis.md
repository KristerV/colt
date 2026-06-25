# Enrichment cost analysis

_Snapshot: 2026-06-25 (current month). Source: `/admin/costs` "THIS MONTH · BY TASK"._

## Spend by task

| task | provider | calls | $ | model tier |
|---|---|---|---:|---|
| google_search | google_cse | 29,873 | 108.57 | — (per-query) |
| extract_contacts | openrouter | 3,192 | 63.20 | `:smart` (gemini-3.5-flash) |
| pick_best_result | openrouter | 30,016 | 29.40 | `:cheap` (glm-4.7) |
| classify_icp | openrouter | 6,662 | 21.35 | `:smart` |
| pick_contact_paths | openrouter | 12,437 | 19.60 | `:cheap` |
| summarize_landing | openrouter | 8,592 | 18.12 | `:cheap` |
| pick_best_contact | openrouter | 2,298 | 2.33 | `:cheap` |
| email_writer | openrouter | 43 | 1.14 | — |
| (others) | openrouter | <60 | <0.40 | — |

**Total ≈ $264/month.**

## Why google_search is the top line

It is **not a token cost.** Provider is `google_cse` (Google Custom Search), billed
**per query at a flat $0.005**, hardcoded in `lib/colt/services/search/google.ex:14`.
`$108.57 ÷ 29,873 ≈ $0.0036/query` — the gap vs $0.005 is the free-tier overstatement
the moduledoc admits to (real bill ≈ $93). It tops the chart on **volume**, not token weight.

A search fires once per company with no registry website, or whose registry URL fails the
liveness check (`check_website.ex:43-44`, `:dead` at :56). Already deduped at the **Company**
level via `touch_website_searched` + `Freshness.website_search_fresh?`, so cross-campaign
re-searches are mostly avoided. The 30k volume is genuine: that many companies lack a usable
registry website.

## The funnel is top-heavy

| stage | calls | yield |
|---|---:|---|
| google_search | 29,873 | — |
| pick_best_result | 30,016 | 1:1 — one LLM pick per search |
| summarize_landing | 8,592 | only **29%** of searches yield a usable site |
| classify_icp | 6,662 | |
| extract_contacts | 3,192 | |

**~71% of searches find no usable website**, yet each still pays $0.005 for the search
*plus* a `pick_best_result` LLM call. So **google_search + pick_best_result ≈ $138 (52% of
total)**, most of it spent on companies that go nowhere.

## Cost-cutting levers (in priority order)

1. **Switch search provider — biggest single win, deferred.**
   Google CSE at $0.005/query is among the priciest options. Serper.dev (~$0.001) or
   Brave Search API (~$0.002) are 2.5–5× cheaper for equivalent results. Swapping behind
   the existing `Search.Google` seam would take the $108 line to **~$22–43**.
   _Decision (2026-06-25): doable, but not doing it right now._

2. **Replace `pick_best_result`'s LLM with a heuristic** (~$29 + 30k LLM calls saved).
   Picking the real site out of 10 results is mostly a domain-name match; the code comment
   already names the junk to exclude (teatmik.ee, infoturg.ee, registries). A fuzzy
   domain↔name match with a directory blocklist handles the common case; fall back to the
   LLM only on ambiguity. It currently fires on every search, including the 71% that are useless.
   _Note: this task already runs on `:cheap` (glm-4.7) — not a tier-downgrade opportunity;
   the win is skipping the LLM entirely for the common case._

3. **Pre-filter before searching — NOT doable.**
   ICP classification needs the landing page, so it can't gate the search, and registry
   metadata isn't sufficient to rule companies out beforehand. _Ruled out (2026-06-25)._

## Other notes

- `extract_contacts` is the #2 cost ($63, only 3,192 calls ≈ $0.02 each): `:smart`
  (gemini-3.5-flash) over large scraped-page context. A separate pass could trim that
  context or route to a cheaper tier if needed.
- All `pick_*` / `summarize_landing` tasks already run on `:cheap`. The `:smart`-tier tasks
  are `extract_contacts`, `classify_icp`, and the two `generate_*_learning` tasks.
- Model tiers are defined in `config/config.exs:18-21` (`cheap: z-ai/glm-4.7`,
  `smart: google/gemini-3.5-flash`).
