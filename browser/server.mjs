// Colt stealth browser sidecar — the single browser for ALL scraping in the system.
//
// One patchright (stealth-patched chromium) instance, headed under Xvfb, requests
// serialized. Elixir talks to it over localhost HTTP (see lib/colt/services/browser.ex).
// It clears Cloudflare managed challenges that plain Req and stock headless chromium
// cannot (verified: stock/headless/Thorium all blocked; patchright-headed-under-Xvfb
// clears in ~17s, even in a displayless container).
//
// Run (container):  xvfb-run -a node server.mjs
// Env:
//   COLT_BROWSER_PORT        listen port (default 8791)
//   COLT_BROWSER_PROFILE     persistent profile dir (default /tmp/colt-browser-profile)
//   COLT_BROWSER_CONCURRENCY max simultaneous tabs in the one browser (default 4)
import http from 'node:http';
import { chromium } from 'patchright';

const PORT = parseInt(process.env.COLT_BROWSER_PORT || '8791', 10);
const PROFILE_DIR = process.env.COLT_BROWSER_PROFILE || '/tmp/colt-browser-profile';
const CHALLENGE_TITLE = 'Just a moment';

let ctx = null;
let launching = null;

async function getContext() {
  if (ctx) return ctx;
  if (launching) return launching;
  launching = chromium
    .launchPersistentContext(PROFILE_DIR, { headless: false, viewport: null, args: ['--no-sandbox'] })
    .then((c) => {
      c.on('close', () => { ctx = null; });
      ctx = c;
      launching = null;
      return c;
    })
    .catch((e) => { launching = null; throw e; });
  return launching;
}

// Bounded concurrency — one warm browser, up to N tabs at once (default 4, matching
// the old CDP path's parallelism). Tabs share the context's cookies, so the Cloudflare
// clearance carries across them. Override with COLT_BROWSER_CONCURRENCY.
const CONCURRENCY = Math.max(1, parseInt(process.env.COLT_BROWSER_CONCURRENCY || '4', 10));
let active = 0;
const waiters = [];

function acquire() {
  if (active < CONCURRENCY) {
    active++;
    return Promise.resolve();
  }
  return new Promise((resolve) => waiters.push(resolve));
}

function release() {
  const next = waiters.shift();
  if (next) next();
  else active--;
}

async function withSlot(fn) {
  await acquire();
  try {
    return await fn();
  } finally {
    release();
  }
}

// Navigate and wait until the Cloudflare challenge clears (title stops being
// "Just a moment"). Returns the page, ready for evaluate/content.
async function openCleared(url, timeoutMs) {
  const c = await getContext();
  const page = await c.newPage();
  const deadline = Date.now() + timeoutMs;
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeoutMs }).catch(() => {});
    while (Date.now() < deadline) {
      const title = await page.title().catch(() => '');
      if (!title.includes(CHALLENGE_TITLE)) return page;
      await page.waitForTimeout(1500);
    }
    throw new Error('cloudflare_challenge_not_cleared');
  } catch (e) {
    await page.close().catch(() => {});
    throw e;
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let b = '';
    req.on('data', (d) => { b += d; if (b.length > 5e6) req.destroy(); });
    req.on('end', () => resolve(b));
    req.on('error', reject);
  });
}
const json = (res, code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && req.url === '/health') return json(res, 200, { ok: true, browser: !!ctx });

    // Navigate to `url` (clearing CF) and return the fully-rendered HTML.
    // Mirrors the {html, status, final_url} contract the old CDP fetcher returned.
    if (req.method === 'POST' && req.url === '/fetch') {
      const { url, timeout_ms = 60000 } = JSON.parse((await readBody(req)) || '{}');
      if (!url) return json(res, 400, { error: 'url required' });
      const out = await withSlot(async () => {
        const page = await openCleared(url, timeout_ms);
        try { return { url: page.url(), title: await page.title(), html: await page.content() }; }
        finally { await page.close().catch(() => {}); }
      });
      return json(res, 200, out);
    }

    // Navigate to `url` (clearing CF), then run `fn` (async function body string) in
    // the page context and return its JSON value. Used by scrapers that page an API.
    if (req.method === 'POST' && req.url === '/eval') {
      const { url, fn, timeout_ms = 120000 } = JSON.parse((await readBody(req)) || '{}');
      if (!url || !fn) return json(res, 400, { error: 'url and fn required' });
      const out = await withSlot(async () => {
        const page = await openCleared(url, timeout_ms);
        try { return { result: await page.evaluate(`(async () => { ${fn} })()`) }; }
        finally { await page.close().catch(() => {}); }
      });
      return json(res, 200, out);
    }

    json(res, 404, { error: 'not found' });
  } catch (e) {
    json(res, 500, { error: String((e && e.message) || e) });
  }
});

server.listen(PORT, '127.0.0.1', () => console.log(`colt-browser listening on 127.0.0.1:${PORT}`));
