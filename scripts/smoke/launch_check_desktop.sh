#!/usr/bin/env bash
# Launches a built desktop app (Linux or macOS), watches it for WATCH_SECONDS
# and fails if it exits or reports a crash. Leaves a screenshot and the app's
# output in OUT_DIR for the run's artifacts.
#
#   bash scripts/smoke/launch_check_desktop.sh <executable>
#
# On Linux run it inside scripts/smoke/linux_session.sh (display + keyring).
set -uo pipefail

exe="$1"
OUT_DIR="${OUT_DIR:-build/smoke}"
WATCH_SECONDS="${WATCH_SECONDS:-30}"
mkdir -p "$OUT_DIR"
log="$OUT_DIR/app-output.txt"

[ -x "$exe" ] || { echo "Not an executable: $exe" >&2; exit 2; }

echo "== Launching $exe =="
"$exe" >"$log" 2>&1 &
pid=$!

alive=1
for i in $(seq 1 "$WATCH_SECONDS"); do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "  ~${i}s: the app exited"
    alive=0
    break
  fi
  sleep 1
done

echo "== Screenshot =="
case "$(uname -s)" in
  Linux) import -window root "$OUT_DIR/screenshot.png" 2>/dev/null || echo "  (no screenshot)" ;;
  Darwin) screencapture -x "$OUT_DIR/screenshot.png" 2>/dev/null || echo "  (no screenshot)" ;;
esac

crash=0
if grep -qE "Unhandled Exception|Segmentation fault|SIGSEGV|SIGABRT|Abort trap" "$log"; then
  crash=1
fi
if [ "$(uname -s)" = Darwin ]; then
  # A crash on macOS leaves a report even when the process is gone quietly.
  name="$(basename "$exe")"
  if ls "$HOME/Library/Logs/DiagnosticReports/" 2>/dev/null | grep -q "^${name}"; then
    cp "$HOME/Library/Logs/DiagnosticReports/${name}"* "$OUT_DIR/" 2>/dev/null || true
    crash=1
  fi
fi

kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

echo "============== APP OUTPUT (tail) =============="
tail -80 "$log"
echo "==============================================="
if [ "$alive" = 0 ] || [ "$crash" = 1 ]; then
  echo "RESULT: the app crashed or exited within ${WATCH_SECONDS}s." >&2
  exit 1
fi
echo "RESULT: app stayed alive ${WATCH_SECONDS}s — no crash detected."
