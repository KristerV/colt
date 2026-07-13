# colt-browser

The **single browser** for all scraping in Colt. A small Node HTTP sidecar wrapping
[patchright](https://github.com/Kaliiiiiiiiii-Vinyzu/patchright) (a stealth-patched
Playwright/Chromium), run **headed under Xvfb**. Elixir talks to it over localhost HTTP
via `Colt.Services.Browser`.

## Why this exists

Some registry sources (notably Lithuania's Sodra, `atvira.sodra.lt`) sit behind a
Cloudflare **managed challenge**. Empirically:

| Browser | Clears the challenge? |
|---|---|
| Plain `Req` / curl | ❌ |
| Stock chromium `--headless=new` (any UA / stealth init) | ❌ |
| Stock chromium / Playwright headed (Xvfb or real display) | ❌ |
| Thorium automated, headed | ❌ |
| Patchright **headless** (headless-shell) | ❌ |
| **Patchright headed under Xvfb** | ✅ ~17s (works in a displayless container) |

So automation requires **both** a stealth-patched browser **and** a real (virtual)
display. This sidecar is that browser, and it is the only one — the CDP/chromium and
Wallaby paths are replaced by `Colt.Services.Browser` → this service.

## API (localhost only)

- `GET  /health` → `{ ok, browser }`
- `POST /fetch` `{ url, timeout_ms }` → `{ url, title, html }` — rendered HTML after CF clears.
- `POST /eval`  `{ url, fn, timeout_ms }` → `{ result }` — navigates (clearing CF), then runs
  `fn` (an async function **body** string) in the page context and returns its JSON value.
  Used by scrapers that page a JSON API from inside the cleared origin.

One warm browser handles up to `COLT_BROWSER_CONCURRENCY` tabs at once (default 4,
matching the old CDP path). Tabs share the context, so the Cloudflare clearance cookie
carries across them and subsequent calls to a cleared origin are fast.

## Run

```sh
npm install
npx patchright install --with-deps chromium   # patched chromium + system deps
xvfb-run -a node server.mjs                    # headed, on a virtual display
```

In production this is launched from `rel/overlays/bin/entrypoint.sh` under Xvfb, before
the Elixir release starts.

## Caveat

This is an anti-detection arms race. If Cloudflare tightens and `/fetch`//`eval` start
returning `cloudflare_challenge_not_cleared`, bump `patchright` and its chromium. The
Sodra ingest surfaces this as a failed Oban job — monitor for it.
