#!/usr/bin/env bash
set -euo pipefail

# Session dbus — without it, Chromium burns ~40s probing the (missing) system bus.
dbus-daemon --session --fork --address=unix:path=/tmp/dbus-session.sock
export DBUS_SESSION_BUS_ADDRESS="unix:path=/tmp/dbus-session.sock"

CHROME_PORT="${CHROME_PORT:-9222}"
CHROME_LOG="${CHROME_LOG:-/tmp/chromium.log}"

# Boot Chromium once. Subsequent fetches open tabs against this same process via
# CDP (lib/colt/services/scrape/cdp.ex), so the cold-start cost is paid here.
chromium \
  --headless=new \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-background-networking \
  --disable-sync \
  --disable-default-apps \
  --disable-component-update \
  --disable-extensions \
  --no-first-run \
  --no-default-browser-check \
  --disable-features=Translate,InterestFeedContentSuggestions \
  --disable-gpu \
  --mute-audio \
  --metrics-recording-only \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port="${CHROME_PORT}" \
  --remote-allow-origins=* \
  >"${CHROME_LOG}" 2>&1 &

CHROME_PID=$!

# Wait for the debugger endpoint to answer. /json/version is the canonical probe.
for i in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${CHROME_PORT}/json/version" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "${CHROME_PID}" 2>/dev/null; then
    echo "chromium exited before debugger came up; see ${CHROME_LOG}" >&2
    exit 1
  fi
  sleep 1
done

exec /app/bin/server
