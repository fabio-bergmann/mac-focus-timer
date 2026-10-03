#!/usr/bin/env bash
# The "localhost" for this app. Builds the working tree, uncommitted edits
# included, as "Focus Timer Dev" and relaunches it whenever a source file
# changes. It runs beside the installed app with its own settings, timer and
# shortcut (⌃⌥Space), and carries an orange dot in the menu bar.
#
#   scripts/dev.sh     # leave it running in a terminal tab; Ctrl-C stops it
#
# A build that fails prints its errors and leaves the last good build running.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Focus Timer Dev.app"
BIN="$APP/Contents/MacOS/FocusTimer"
LOG="$(mktemp -t focus-timer-dev)"
PID=""

stop_app() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
  fi
  PID=""
}
trap 'stop_app; rm -f "$LOG"; echo; echo "Stopped."; exit 0' INT TERM

# Changes whenever a file that shapes the build is edited, added or removed.
fingerprint() {
  find "$ROOT/Sources" "$ROOT/Support" "$ROOT/Package.swift" "$ROOT/scripts/build-app.sh" \
    -type f -exec stat -f '%m %N' {} + | shasum | cut -d' ' -f1
}

rebuild() {
  local started=$SECONDS
  if FOCUS_TIMER_VARIANT=dev bash "$ROOT/scripts/build-app.sh" >"$LOG" 2>&1; then
    stop_app
    "$BIN" &
    PID=$!
    echo "$(date +%H:%M:%S)  running ($((SECONDS - started))s build)"
  else
    # Just the compiler's file:line errors, once each; the tail if there are none.
    grep -E "^error: /" "$LOG" | sed 's/: FixIt(.*//' | awk '!seen[$0]++'
    grep -qE "^error: /" "$LOG" || tail -15 "$LOG"
    echo "$(date +%H:%M:%S)  build failed; the last good build keeps running"
  fi
}

echo "Focus Timer Dev: watching $ROOT (Ctrl-C to stop)"
# A copy left behind by an earlier run would make the new one quit on launch.
pkill -f "$BIN" 2>/dev/null

last=""
while true; do
  current="$(fingerprint)"
  if [ "$current" != "$last" ]; then
    # Taken before the build, so edits that land while it runs trigger another.
    last="$current"
    rebuild
  fi
  sleep 1
done
