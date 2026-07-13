#!/usr/bin/env bash
set -euo pipefail

# Session dbus — without it, Chromium burns ~40s probing the (missing) system bus.
dbus-daemon --session --fork --address=unix:path=/tmp/dbus-session.sock
export DBUS_SESSION_BUS_ADDRESS="unix:path=/tmp/dbus-session.sock"

# Virtual display for the stealth browser. It runs *headed* under Xvfb — headless
# chromium (any flavour) is detected and blocked by Cloudflare; patchright-headed-
# under-Xvfb clears it. See browser/README.md.
export DISPLAY="${DISPLAY:-:99}"
Xvfb "${DISPLAY}" -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &

# The single scraping browser sidecar. Elixir talks to it on localhost
# (lib/colt/services/browser.ex).
COLT_BROWSER_PORT="${COLT_BROWSER_PORT:-8791}"
BROWSER_LOG="${BROWSER_LOG:-/tmp/colt-browser.log}"
( cd /app/browser && node server.mjs >"${BROWSER_LOG}" 2>&1 ) &
BROWSER_PID=$!

# Wait for the sidecar HTTP server to answer before starting the app.
for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${COLT_BROWSER_PORT}/health" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "${BROWSER_PID}" 2>/dev/null; then
    echo "colt-browser sidecar exited before it came up; see ${BROWSER_LOG}" >&2
    cat "${BROWSER_LOG}" >&2 || true
    exit 1
  fi
  sleep 1
done

exec /app/bin/server
