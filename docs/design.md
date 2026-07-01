# Design system — Liid ("Calm Pro")

> **Product name in the UI is "Liid".** The repo is `colt` (working name); the user-facing brand is **Liid**. Use Liid in all copy, page titles, the wordmark, and the marketing surface. Use `colt` only for the OTP app name and module namespace.

**Source of truth: the living prototype in `priv/design_demos/`.** When implementing any UI, open the relevant demo file there and match it. This document distills the system; the demo files are the reference.

- App interface (the design we ship): `priv/design_demos/d1-calm.html` — the "Calm Pro" sending-funnel screen. This is the canonical app look: sidebar + headline + stat boxes + a two-column list/thread body.
- Landing / marketing page: `priv/design_demos/landing/l0-combined.html` — the agreed landing layout. Other `l1…l6` files in that folder are earlier explorations; `l0` is the one we ship.
- The funnel switcher `priv/design_demos/index.html` lets you flip designs 1–6; we chose **#1 Calm Pro**.

> The older `priv/design_prototype/` (the warm-paper / serif / hairline-rule system with oklch forest-green accent) is **superseded** by Calm Pro and kept only for history. Do not match it.

## 0. The feel — what "Calm Pro" means

Direction, set with the user over a long design review:

- **Light, calm, approachable.** Warm off-white canvas, soft charcoal ink. No dark mode, no glow, no terminal/console look, no neon.
- **Compartmentalized.** *Every meaningful unit is its own bounded box.* One email = one card with all of its own metadata inside its own border. Buckets, notes, the composer, list rows — each is a self-contained box. This is the single most important rule.
- **Contrast comes from real boxes**, not from a lone faint hairline. **Never separate sections with a single thin divider rule.** Use bordered, softly-shadowed cards with clear gaps between them.
- **Restrained, functional color.** Color is welcome but contained: the accent blue for emphasis / primary actions / the active state; green / amber / red **only** as small status chips and dots. Never a loud multi-color scheme — this is a tool for salespeople; it must read clear and trustworthy.
- **Operator / blunt copy** — numbers-driven, no fluff: "500 companies match", "Stop sending to dead inboxes", "One tool, not five."

## 1. Tokens

All values are plain sRGB hex (the app previously used oklch; Calm Pro uses hex for parity with the prototype). Tokens live in `assets/css/app.css` — both as Tailwind v4 `@theme` (utility classes like `bg-card`, `text-ink`, `text-accent`) and as `:root` CSS vars (read directly by inline `style=` in components, e.g. `var(--accent)`).

```
/* surfaces */
bg          #f7f7f5     /* warm off-white page canvas (set on <body>) */
bg-soft     #fbfbfa     /* slightly lighter inset lane (e.g. the thread scroll area) */
card        #ffffff     /* every bounded card/box */
paperAlt    #f2f2ef     /* hover / pressed soft fill */

/* ink (text) */
ink         #37352f     /* primary text — soft charcoal, NOT pure black */
ink-soft    #6b6862     /* secondary text */
ink-faint   #97948d     /* tertiary text, placeholders, captions, ticks */

/* lines */
border        #e3e3e0   /* default card border */
border-strong #d6d6d1   /* heavier border / secondary-button outline */

/* accent — the single brand color */
accent      #3b7ae0     /* calm blue: primary buttons, active state, emphasis, links */
accent-soft #eef3fc     /* pale accent wash — active bucket / selected row fill */
accent-ring #bcd2f5     /* accent border/ring on active elements */

/* functional status — small chips & dots only */
green       #2f9e6b   green-soft #e7f5ee   /* interested / sent / verified / good */
amber       #c98a1e   amber-soft #fbf1dd   /* bounced / warning / notes */
red         #d05a4f   red-soft   #fbeae8   /* failed / hard errors */
gold        #c9a227   gold-soft  #faf4dc   /* admin-only "golden" features, pre-GA */
```

**Golden = admin-only, GA-bound.** Features gated to admins now but slated to ship to
everyone later are marked with the gold token and a `<Liid.admin_badge />` chip, so it's
obvious at a glance which surfaces are pre-release. Not a functional status colour — a
convention marker.

Existing semantic class names from the old system are **remapped, not removed** — `bg-paper` now resolves to white (`card`), `border-rule`/`border-ink20` to `border`, `text-ink55` to a faint ink, `text-accent` to the blue. So legacy markup keeps working; new markup should prefer the names above.

### Shadows & shape

```
--shadow       0 1px 2px rgba(35,32,28,.05), 0 2px 6px rgba(35,32,28,.04)   /* default card */
--shadow-card  0 1px 2px rgba(35,32,28,.06), 0 4px 12px rgba(35,32,28,.05)  /* primary panels (list, thread) */
radius         11px   (cards, panels)
radius-sm      8px    (inputs, buttons, chips, nav items)
```

Border radius is **11px / 8px — soft, not sharp.** (The old system's 2px is gone. Sweep any hardcoded `rounded-[2px]` to `rounded-[11px]` / `rounded-lg`.)

### Type — **Inter only**

```
sans   "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif    /* everything */
```

Load Inter from Google Fonts at weights `400;450;500;600;700`, with `-webkit-font-smoothing:antialiased`. **No serif, no monospace.** (The old Inter Tight / Instrument Serif / JetBrains Mono trio is retired. `--font-serif` and `--font-mono` are aliased to Inter so legacy `font-serif`/`font-mono` classes render as Inter; strip them when you touch a file.)

Type scale (match the prototype):

| Use | Size / weight / tracking |
|---|---|
| Page headline (with one italic accent word) | 25px / 600 / -0.02em |
| Section heading (landing) | 30–40px / 600–700 / -0.02em |
| Card / thread name | 17px / 700 |
| Big stat number (bucket) | 27px / 700 / -0.02em, tabular-nums |
| Body | 13–15px / 400–450 |
| Label / chip (small caps optional) | 10.5–11.5px / 600, uppercase +0.08em where used |

The `<em>` element is globally rebound to **italic + accent color** (still Inter, not serif) — use it for the one emphasized word in a heading, e.g. "Where the <em>conversation</em> is going." Always `font-variant-numeric: tabular-nums` on numbers, stats, counts, and progress (`.tnum` / `.tabular-nums`).

## 2. Components — the recipes

When implementing in Phoenix, recreate these as function components / heex. The reference markup is in `priv/design_demos/d1-calm.html` (app) and `landing/l0-combined.html` (marketing). Don't approximate from memory — open the file.

### Card (the atom)
White `card` background, `1px solid border`, `--shadow`, `radius:11px`. Everything compartmentalized is a card. Cards sit on the `bg` canvas with **visible gaps** between them (≈12–16px). A card may carry a small meta header row inside it (chips + timestamp) above its body.

### Sidebar
Fixed ~248px left column on `bg-soft`, `1px` right border. Top: the wordmark — a 26px rounded (7px) accent-blue square with a white "L" + "Liid" 18px bold. A small white "Campaign" card showing the active campaign name. Nav groups (uppercase faint group label + items). A nav item is `8px` radius, `ink-soft`; **active item** = `accent-soft` fill, `accent` text, `inset 0 0 0 1px accent-ring`, weight 600. Footer: Email accounts / Billing / Feedback + a user row (28px avatar + email).

### Bucket / stat box
White card, label (11.5px, `ink-soft`) + big tabular number (27px, 700) + a faint sub-line. **Active** bucket = `accent-soft` fill, `accent-ring` border + ring, accent label & number. A "live" bucket shows a green dot with a pulsing halo. Error/warn buckets tint only the sub-line red/amber.

### Contact / list row
A row inside the list card: a 34px rounded-square avatar (initials), name (600) + title (`ink-faint`) + a small status line (green dot + "replied · interested"), and a right-aligned progress pill ("3/4", tabular). **Selected** row = `accent-soft` fill + `accent-ring` inset; its avatar and progress pill go accent-tinted.

### Email card (timeline)
Its own bounded card. A meta row (chips: "Step 1", "You", "Sent", + timestamp) sits inside the card above a bold subject + body. Outbound aligns left, inbound aligns right (inbound border + meta tinted `accent-soft`). A **note** is a distinct `amber-soft` card with an amber "Note" chip. Chips are small rounded tinted pills (`step` grey, `you/them` accent, `sent` green, `manual` violet, `note` amber).

### Thread pane (compartmentalized scroll)
The right column is a `bg-soft` bordered scroll **lane** holding three+ separate cards: the **company-info header card**, the stack of **email cards**, and the **reply composer card** — each its own block, scrolling together with gaps. (Do **not** make the whole pane one card that scrolls, and do **not** pin the header/composer.)

### Buttons
- **Primary**: `accent` bg, white text, `radius:8px`, soft accent shadow, weight 600. (e.g. "Send reply", "Start a campaign".)
- **Secondary**: white bg, `border-strong` outline, `ink-soft` text.
- **Tabs** (composer Reply/Note): active tab = `accent-soft` fill + `accent` text + ring.

### Animations
`pulse` halo for live/active dots (`scale .6→1.9, opacity .5→0, 1.8s infinite`). Keep motion subtle. No shimmer/CRT/blink.

## 3. Landing page

Ship `priv/design_demos/landing/l0-combined.html`. Structure, in order: sticky nav → hero (the 4-step funnel **Filter → Enrich → Send → Interested** as the focal visual, narrowing counts 300k → 10k → 2,400 → 230) → "Everything you need for cold outreach" (the full app UI mock) → step-by-step walkthrough (numbered spine 01–06, **text left / visual right on every row, never alternating**, ending on Calling) → low on the page: the "100 prospects" time-comparison table (By hand / Apollo + automation tools / Liid — explains *why* each approach is slow) → "One tool, not five." (the stack it replaces) → pricing (€49 / €159 "Most popular" / €699) → final CTA "Stop sending to dead inboxes." → footer. Inter throughout, the same Calm Pro tokens, no serif. No speed promises; comparison times are labelled illustrative.

## 4. Hard rules (quick reference for any UI work)

1. Brand name in all UI copy is **Liid**.
2. Use the Calm Pro tokens in §1 (and `assets/css/app.css`). Don't substitute raw Tailwind grays.
3. **Inter only.** No serif, no mono.
4. **Everything is a box.** One email = one card; buckets, notes, composer, rows are each their own bounded, softly-shadowed card with gaps. Never divide sections with a single faint hairline.
5. Border radius **11px / 8px**. Soft by intent.
6. **Restrained color**: accent blue for emphasis/active/CTA; green/amber/red only as small chips & dots.
7. Tabular-nums on all numbers.
8. Match the demo files in `priv/design_demos/`, not memory.
