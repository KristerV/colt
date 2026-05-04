# Design system — Liid

> **Product name in the UI is "Liid".** The repo is `colt` (working name); the user-facing brand is **Liid**. Use Liid in all copy, page titles, the wordmark, and the marketing surface. Use `colt` only for the OTP app name and module namespace if you keep it.

The full design prototype lives at `priv/design_prototype/`. **When implementing any UI, open the relevant file there and match it.** This document distills the system; the prototype is the source of truth.

Direction set in the design chat:
- **Minimal Scandi** — warm paper, generous whitespace, serif accents
- **Operator / blunt** copy — "500 companies match", "Take 312 enriched companies somewhere"
- Static layouts in the prototype; interactivity is our job to add

## 1. Tokens

All colors are **oklch**. Don't convert to hex; modern browsers support oklch and the perceptual uniformity matters when the user tweaks the accent.

```
paper      oklch(98% 0.005 80)        /* warm off-white */
paperAlt   oklch(96% 0.006 80)        /* card / hover surface */
ink        oklch(20% 0.012 250)       /* near-black, slightly cool */
ink70      ink @ 70% alpha            /* secondary text */
ink55      ink @ 55% alpha            /* tertiary text */
ink40      ink @ 40% alpha            /* placeholders, ticks */
ink20      ink @ 20% alpha            /* borders */
ink10      ink @ 10% alpha            /* progress track bg */
rule       ink @ 12% alpha            /* hairline dividers */

accent     oklch(55% 0.13 145)        /* default forest green */
accentSoft oklch(94% 0.04 145)        /* very pale accent wash */
warn       oklch(60% 0.13 60)         /* amber — fallback search, etc. */
fail       oklch(58% 0.18 28)         /* red — hard errors */
ok         oklch(55% 0.12 145)        /* same family as accent */
```

Accent presets the user can pick from: forest `#3d7a3d`, ink `#1f2937`, rust `#b85c3a`, cobalt `#2a52be`. Accent is set as a CSS custom property `--accent` on the screen root and consumed by status dots, primary buttons, progress bars, etc. Plan for runtime theming.

### Type

```
sans     "Inter Tight", "Inter", system-ui, sans-serif    /* UI */
serif    "Instrument Serif", Georgia, serif               /* display accents only */
mono     "JetBrains Mono", ui-monospace, Menlo, monospace /* numbers, labels, log */
```

Load all three from Google Fonts. The `<em>` element is hard-rebound to the serif globally.

Type scale (used in the prototype — match these):

| Use                         | Family         | Size | Weight | Letter-spacing |
|-----------------------------|----------------|------|--------|----------------|
| Hero / display heading       | serif          | 64   | 400    | -1.4           |
| View 4 page title           | serif          | 44   | 400    | -0.8           |
| Counter (View 3 "847")      | serif          | 76   | 400    | -2.0           |
| Card title (markets, modal) | serif          | 32–38| 400    | -0.6           |
| Body                        | sans           | 13–15| 400/500| 0              |
| Label (uppercase mono)      | mono           | 10–11| 400    | +0.08–0.12     |
| Data / numbers              | mono           | 10–12| 400/500| +0.04          |
| Stepper segment             | mono           | 11   | 400/600| +0.04 (+0.08 on label, uppercase) |

Always use `font-variant-numeric: tabular-nums` on counters and table data.

### Spacing & shape

- **Border radius**: 2px on cards, inputs, buttons, pills. Sharp by intent.
- **Borders**: 1px solid `ink20` for default, 1px solid `ink` for selected, 1px solid `accent` for active.
- **Density**: prototype has a `density` token (`compact` | `comfy`). Comfy uses screen padding `40px / 56px` (y/x), compact `28px / 32px`. Inside cards, padding shrinks proportionally. Implement as a user-toggleable setting.

### Animation

Defined in `liid-shared.jsx` keyframes:

```
liid-pulse     scale .85→1, opacity .55→1, 1.4s ease-in-out infinite
liid-blink     opacity 1/0, 1s steps(1) infinite (cursor)
liid-shimmer   linear-gradient swept across width, 1.8s linear infinite
liid-tick      width 0→var(--w), used for progress bar fills
```

Use `liid-pulse` for any "currently active" indicator (running workers, live preview, status dots in `work` state). Use `liid-shimmer` for skeleton placeholders in table cells while data loads.

### Iconography

Hairline 1.25px stroke, 16×16 viewBox, `currentColor`. Path data is in `priv/design_prototype/project/liid-shared.jsx` under `LiidIcon`. Available: `arrow, chev, chevR, chevL, plus, x, check, search, globe, spark, download, file, user, mail, link, code, filter, grid`. **Reuse this set verbatim; don't pull in lucide/heroicons.**

## 2. Components

Component file map in the prototype:

| File | What's in it |
|---|---|
| `liid-shared.jsx` | tokens, `StatusDot`, `LiidIcon`, `LiidScreen`, `LiidTopBar` (wordmark + stepper + campaign chip + avatar), `LiidBtn`, `LiidH` (kicker + serif headline + sub) |
| `views-0-2.jsx` | View 0 (campaign name), View 1 (ICP + job titles), View 2 (market) |
| `view-3.jsx` | Filter panel + counter + live preview + `Fset`, `GrowthGlyph` |
| `view-4.jsx` | Funnel hero, `StatsStrip`, `FunnelRow`, three viz styles, `ExpandedDetail`, `ExportModal` |
| `data.jsx` | Mock company seeds, `STAGE_KEYS`, `STAGE_LABEL`, `ROW_STATES` |

When implementing in Phoenix LiveView, recreate these as function components / heex partials. Don't try to port the JSX structure 1:1 — match the visual output. Patterns to keep:

### TopBar / stepper
Stepper labels (uppercase mono, padding 6/12, hairline dividers between segments):
```
00 NAME — 01 ICP — 02 MARKET — 03 FILTERS — 04 FUNNEL
```
Active step: ink color + accent number + weight 600. Done: ink55. Future: ink40.

The campaign name + user avatar live on the right. Avatar is a 24px ink-filled circle with a single uppercase initial in paper.

### Status dot (`StatusDot`)
6–8px circle with optional outer halo (`accent22` 3px box-shadow) and `liid-pulse` animation when state is `work`. State-to-color:
- `idle` → ink20 outline only
- `work` → accent fill + pulse + halo
- `done` → accent fill
- `skip` → ink40 fill
- `fall` → warn fill (used for fallback states like Google search)
- `fail` → fail fill

### Buttons (`LiidBtn`)
- **Primary**: ink background, paper text, ink border, 10/18 padding (7/12 small), 13px font, weight 500. Mono variant has letter-spacing 0.04.
- **Secondary**: transparent bg, ink20 border, ink text.
- Border radius 2px. Always pair with a small inline icon when there's room.

### Headlines (`LiidH`)
Three pieces: kicker (mono uppercase, ink55), title (serif 64, line-height 1.02), sub (sans 15, ink55, max-width 520). Title supports an embedded `<em>` rendered in `Instrument Serif` italic + accent color — used to give every page a single accented word. Examples: "What are we calling this *hunt*?", "Describe the *customer* you want.", "Narrow the *funnel*.", "Which *register* do we pull from?". **Keep the one-italicized-word pattern on every step.**

## 3. Per-view layout

### View 0 — name campaign
Open file: `priv/design_prototype/project/views-0-2.jsx` lines 5–76.
- LiidH on the left (max-width 760).
- Below: serif input, max-width 560, 44px text, no border except 1px bottom rule on ink, transparent bg.
- Status line under the input in mono ink55: `● draft · auto-saved 0s ago` (the dot is accent).
- Continue button (primary mono with arrow icon) + ⏎ to continue hint.
- Right side: 240px-wide "Recent" sidebar with a left rule, listing 4 recent campaigns: name, `ratio` (e.g. `847 / 1,000`), and relative time. List items separated by hairline rules.

### View 1 — ICP + target titles
Open file: `views-0-2.jsx` lines 78–177.
Two-column layout with 64px gap. Left: 320px LiidH ("Describe the *customer* you want."). Right: max-width 640.
- ICP textarea: label (mono uppercase) on the left, `length / 2000` counter on the right. Box: ink20 border, paperAlt bg, 20/22 padding, 15/1.55 type, min-height 200, blinking accent caret at the end of pasted content.
- **Target job title** (single): one labelled text input. Same paperAlt bg + ink20 border, 12/14 padding, sans 14, blinking accent caret. The prototype's multi-chip pattern is **not** used — see §5.

### View 2 — market
Open file: `views-0-2.jsx` lines 179–269.
- LiidH ("Which *register* do we pull from?").
- Grid of 6 market cards, 3 columns × 2 rows, 14px gap. Each card: 24/24/20 padding, min-height 200, 1px border, 2px radius. Selected card has ink border + paperAlt bg.
- **Active**: EE only (pre-selected). **Disabled**: FI, LV, LT, SE, NO. Disabled cards: opacity 0.45, cursor not-allowed, small uppercase mono **"soon"** badge top-right (the prototype shows "Q3" — use "soon" instead, since we're not gating on a quarter).
- Card content: small radio (14px circle) + 2-letter ISO code (mono, ink55) at top; serif 38px country name + mono row showing API host + company count at bottom.
- Footer: Back + Continue → filters buttons, plus a small mono right-aligned status `<count> active companies in <api> · last sync HH:MM EET`.

### View 3 — filters + live preview
Open file: `priv/design_prototype/project/view-3.jsx`.
Two columns: 360px filter panel + flexible right side.

Filter panel sections (all wrapped in `Fset` — label mono uppercase top-left, optional hint top-right, hairline rule, content):
1. **Industry** — chips, multi-select. Selected: accent bg + paper text. Unselected: ink20 border. `+ N more` chip uses mono.
2. **Employees** — dual-thumb range slider with 1/10/50/500/5k+ scale ticks below.
3. **Trajectory** — checkbox list with mono count on the right. Selected rows have a 2px accent left border and `accent11` background tint.
4. **Region** — same chip pattern as Industry.
5. **Founded** — two inputs separated by an em dash.
6. **Signals** — checkbox list (Has registered website, VAT registered, Filed annual report 2024).

Right side:
- **Counter card**: paperAlt bg, ink20 border. Big serif number (76px, tabular-nums) of matches, `of N` mono caption beside it; on the right, "Funnel cap 1,000" in serif. Below: 6px capacity bar with three quarter-tick marks; mono caption shows `% of cap` and `slots remaining`.
- **Active chips row**: tiny chips listing currently active filter summaries with X icons.
- **Live preview list**: 4-column grid (name | industry | size | growth glyph), 11/16 row padding, hairline row dividers. Header strip at top: pulsing dot + `preview · updated 0.2s ago` left, `showing 12 of 847` right. 60px paper-to-transparent gradient at the bottom edge.
- Footer: Back + primary "Run enrichment on N" with spark icon. **Skip** the prototype's cost estimate (`~ €0.18 / company · est. €152.46`) — see §5.

### View 4 — funnel (hero)
Open file: `priv/design_prototype/project/view-4.jsx`. This is the most important screen.

**Header**: kicker (`05 / Funnel · <campaign name>`), then serif 44px `Enriching <accent>847</accent> companies.` Right side: Filter, Columns, Export buttons (small).

**StatsStrip** — single row of 5 stat tiles, equal flex, hairline borders between, no outer corners but 2px radius on the strip itself:
- Queued / Working / Enriched / ICP miss / Failed
- Each tile: mono uppercase label + percentage on the right; serif 36 number; 2px progress bar below sized as `pct * 2` (capped at 100%).
- "Working" tile has a pulsing dot next to the label and uses accent.
- "Failed" tile uses `fail` color.

**Pipeline meta strip** (mono 11, ink55): `● running · 14 workers · 4.2/s    queue: 422    elapsed: 00:18:42    eta: 00:34:11`. Right-aligned: `sort: status ↓ · 28 of 847 visible`.

**Table**:
- Columns (in compact mode): 24 | 1.5fr | 1fr | 70 | 60 | 2fr | 100 | 1fr
  → checkbox | Company | Industry | Size | Growth | Enrichment | Contact | Status.
- Header: paperAlt bg, mono uppercase ink55.
- Rows: 12/16 padding, hairline bottom rule. Working rows get an `accent06` background tint. Expanded rows get paperAlt.
- Company cell: name (13/500) + mono 10 ink40 sub-line: `domain · registry-code`. Use italic `resolving...` when domain is null.
- Growth cell: 4 vertical bars with heights from a per-bucket map (`shrinking [4,3,2,1]`, `stagnant [3,3,3,3]`, `slow [2,3,4,5]`, `2x [2,4,6,8]`, `10x [2,5,8,11]`). Color-coded.
- Contact cell when done: name (12/500) + mono 10 title sub-line. When `no-contact`: mono `hallucinated` in fail color. When `skip-icp`: mono `—`. When loading: shimmer placeholder.
- Status cell: mono right-aligned, dot + label, dot pulses while working/fallback.

**Enrichment cell — three viz options** (user picks via a setting; ship Pills as default):
- **Pills (default)**: 6 labelled chips with status dots, separated by 4px hairline ticks. Border colors by state. Done: accent14 fill. Working: accent1f fill + pulse.
- **Bar**: 6 segments, 6px tall, 2px gap, full-width flex. Color by state, pulse the working segment. Below: 6 short mono labels (`webs scra pars icp  cont veri`).
- **Log**: single mono line with accent dot if live. Message rendered from row state — examples: `scraping /careers /team /about · 4p found`, `minimising html → markdown · 14kb → 2.1kb`, `asking gpt-4o · "does this match ICP?"`, `verifying email exists in markdown…`. Use `text-overflow: ellipsis`.

**Expanded detail row** (when a row is opened): paperAlt bg, top hairline rule, 20/24/24/56 padding. Two-column grid (1.4fr / 1fr, 32px gap):
- Left: timestamped mono pipeline log (`HH:MM:SS  ✓  message`), 70px / 14px / 1fr grid per line.
- Right: extracted contact card on paper bg, 1px ink20 border. Serif 24 name, ink55 sub `Title · Company`, mono lines for email + source URL with a small `verified` accent label. Bottom: hairline rule + 12/1.5 quote-style "What this company does" summary.

**Export modal**: 640px wide, paper bg, ink20 border, soft 24/80 shadow, full-screen overlay using `rgba(20,18,14,0.45)` + `backdrop-filter: blur(2px)`. Title: kicker + serif 32 `Take N enriched companies somewhere.` 2×3 grid of format cards. CSV is enabled and selected by default; **JSON, HubSpot, Pipedrive, Apollo, Webhook are disabled** with a "soon" badge — see §5. Each card: name (14/600) + mono right-aligned size/note + 12px ink55 description. Below: paperAlt code block previewing the CSV output. Footer: Cancel + primary Download CSV.

## 4. Implementation rules for Phoenix LiveView

- **Recreate, don't transliterate.** The prototype is JSX; we ship heex. Match the rendered pixels, not the React tree.
- **Use CSS custom properties for theming.** Set `--accent` (and others) on a top-level wrapper. All variants (`done`, `work`, `fail`, `warn`) should reference custom properties so the user's accent choice cascades.
- **Keep component boundaries**: `LiidScreen`, `LiidTopBar`, `LiidBtn`, `LiidH`, `StatusDot`, `Fset`, `FunnelRow`, `EnrichmentViz`, `StatsStrip`. One function component per concept, mirroring the prototype.
- **Tailwind**: if we use Tailwind, extend the config with the oklch values as named colors and the three font families. Don't approximate in default Tailwind palette — the warm paper / cool ink combination dies if you use `gray-50` / `gray-900`.
- **Tabular nums** everywhere there's a number in a table or counter.
- **Animations**: copy the four keyframes (`liid-pulse`, `liid-blink`, `liid-shimmer`, `liid-tick`) into our base CSS verbatim.

## 5. Spec/design reconciliation — decisions

All conflicts between the original spec and the prototype have been resolved. Build to these:

| Topic | Decision |
|---|---|
| **Target job title** | Single free-text field on Campaign (per spec). The prototype's multi-chip UI is **not** built — replace with one labelled text input. |
| **Markets** | **EE only** in v1. FI, LV, LT, SE, NO render as disabled cards with a "soon" badge (opacity 0.45, cursor not-allowed, not selectable). EE pre-selected since it's the only option. |
| **Growth buckets** | 5 buckets per design: `:declining, :stagnant, :slow, :growing_2x, :growing_10x`. UI labels: Shrinking / Stagnant / Growing · slow / Growing · 2× / Growing · 10×. |
| **Enrichment stages (visible row)** | 6 visible stages — `web → scrape → parse → icp → contact → verify`. 9 internal Oban jobs map onto these per the table in spec §5.5. |
| **Export modal** | Modal as designed. CSV enabled. JSON / HubSpot / Pipedrive / Apollo / Webhook cards render but are disabled with "soon" badge. |
| **View 0 recent sidebar** | Built. Shows the user's 4 most recent campaigns with `done / total` ratio and relative time. |
| **View 3 cost estimator** | **Not built.** Don't show the `~ €0.18 / company · est. €152.46` line from the prototype. Pricing comes later. |
| **View 4 pipeline meta** | Built. `running · N workers · X/s · queue: N · elapsed · eta` from Oban telemetry, plus the right-aligned `sort · visible / total`. |

## 6. Implementing Liid.html

`Liid.html` itself is a **canvas viewer** — a React harness that lays out all 5 views as artboards on a `#f0eee9` paper background with a Tweaks panel. **Do not port the canvas/tweaks scaffold.** Port the artboard contents (Views 0–4) into LiveViews under `LiidWeb`. The Tweaks panel maps to a real user settings page (`accent`, `density`, `viz` style for the funnel row).

Order of implementation (low risk first):
1. Tokens + global styles + `LiidScreen` + `LiidTopBar` + `LiidBtn` + `LiidH` (used everywhere)
2. View 0 (`/campaigns/new`)
3. View 1
4. View 2
5. View 3 with live counter
6. View 4 with PubSub-driven row updates and Pills viz
7. Bar + Log viz toggles
8. Expanded row detail
9. Export modal (CSV only enabled)
