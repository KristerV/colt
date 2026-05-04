# Baltic Lead Enrichment

_Started 2026-05-04 07:14 UTC_

---

## User

i have nothing but a spec of the app i'm goint to be making.

it's a lead gen thing for balctics and skandinavia. enriching data taken from gov.

* takes in [rik.ee](http://rik.ee) company API
* view 0: new campaign (name)
* view 1: describe your ICP and target job title in free text
* view 2: choose market - estonia or finland
* view 3: use filters to get a good number of companies into your funnel. max is 1000.
* every result is saved btw.
* view 4: companies list. name, size, industry, whatever. then progress, like website found, pages scraped, contacts found, status
* then enrichment begins:
   * check if gov provided website is online, if not
      * google search for the company
      * AI chooses which result is worth looking at
   * visit website with wallaby
   * save list of pages that are in navigation, path only
   * extract generic email from landing with regex
   * minimize html -> markdown, save markdown as page
   * save summary of what company does with AI based on landing markdown
   * ask AI if this company matches ICP
   * ask AI which pages may contain contacts
   * scrape and minimize those pages
   * ask AI for that specific contact we need from said pages
   * immediately validate that AI isn't hallucinating by checking if AI provided email exists in the markdown. if not, it's not a real contact.
   * save contact it under `people` belongs_to `company`

view 4 also has export. in whatever format instantly wants it.

so i want views of the core experience. the search form with realtime results. and the enriching process.

how do we continue?

## Assistant

I'll ask a few targeted questions before building. This is a meaty flow — let's get the direction right.

_[tool: questions_v2]_

## User

Questions answered:
- product_name: Liid
- aesthetic: Minimal Scandi — lots of whitespace, serif accents
- fidelity: Static screens, no interaction
- hero_views: View 4: companies list + enrichment progress
- enrichment_viz: Per-row progress: each company has inline status pills/steps that animate
- filter_realtime: Counter + live preview list of companies updating as you type
- filter_fields: i think you got most. also i'd like if the company is growing, or shrinking or stagnant. and "growing" has a few options, slow, 2x, 10x. 
- icp_input: Textarea + separate target job title field
- market_treatment: Simple radio with country names
- tone: Operator / blunt ("500 companies match")
- scale_hint: Show ~500-1000 to convey scale
- tweaks: Density (compact / comfy), Enrichment viz style, Accent color
- starting_point: No — design from scratch

## Assistant

Great. Committing to the direction now: **Liid** — Minimal Scandi, serif accents, operator-blunt copy, static screens of all 5 views in a design canvas, with the companies list + per-row enrichment as the hero. Tweaks: density, enrichment viz style, accent color.

Type system: **Söhne** isn't free — I'll use **Inter Tight** (UI) + **Instrument Serif** (display accents) + **JetBrains Mono** (data/log). Palette: warm off-white paper `oklch(98% 0.005 80)`, ink `oklch(20% 0.01 250)`, default accent `oklch(55% 0.13 145)` (forest), alt accents teal & rust.

_[tool: update_todos]_

_[tool: copy_starter_component]_

_[tool: copy_starter_component]_

_[tool: read_file]_

_[tool: read_file]_

I have what I need from those reads. Let me snip the read-back of the starter sources, then build.

_[tool: snip]_

Now I'll build out the views. Starting with the data file and individual artboard scripts to keep files manageable.

_[tool: write_file]_

Now the shared style + small components file:

_[tool: write_file]_

_[tool: write_file]_

_[tool: snip]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: snip]_

_[tool: write_file]_

_[tool: done]_

_[tool: snip]_

_[tool: fork_verifier_agent]_

**Liid** is up — design canvas with all 5 views. Direction: warm paper, Instrument Serif display, JetBrains Mono for data, operator-blunt copy.

**Hero (View 4 — funnel & enrichment)** is first and offers 3 viz styles per row, switchable from Tweaks:
- **A · Pills** — labelled step chips with status dots, clearly readable across 28 rows
- **B · Segmented bar** — denser, more dashboard-like
- **C · Live log** — single mono line with the actual current action ("scraping /careers /team /about · 4p found")

Plus **D** (row expanded showing the full timestamped pipeline + extracted contact card) and **E** (export modal — CSV/JSON/HubSpot/Pipedrive/Apollo/Webhook).

**View 3** has the prominent serif counter (847 / 142,180), 1000-cap progress bar, live preview list, and a Trajectory filter with shrinking → stagnant → slow → 2× → 10× as you spec'd.

**Tweaks**: accent color (4 presets — forest, ink, rust, cobalt), density (compact/comfy), enrichment viz style.

Open any artboard fullscreen with the expand button or label click. Let me know what to push on next — likely candidates: empty states, the Wallaby browsing animation, or a settings/auth flow.

