#!/usr/bin/env bash
# Installs a built simulator .app on a booted iOS simulator, launches it,
# watches it for WATCH_SECONDS and fails if it stops or leaves a crash report.
# Leaves a screenshot and the simulator log in OUT_DIR.
#
#   bash scripts/smoke/launch_check_ios_simulator.sh <path/to/App.app> <simulator-udid>
set -uo pipefail

app="$1"
udid="$2"
OUT_DIR="${OUT_DIR:-build/smoke}"
WATCH_SECONDS="${WATCH_SECONDS:-30}"
mkdir -p "$OUT_DIR"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")"
echo "== Installing $bundle_id on $udid =="
xcrun simctl install "$udid" "$app" || { echo "simctl install failed" >&2; exit 2; }

xcrun simctl spawn "$udid" log stream --level error --style compact >"$OUT_DIR/simulator-log.txt" 2>&1 &
log_pid=$!

echo "== Launching =="
launch="$(xcrun simctl launch "$udid" "$bundle_id" 2>&1)" || { echo "$launch" >&2; kill "$log_pid"; exit 1; }
echo "  $launch"

running() {
  xcrun simctl spawn "$udid" launchctl list 2>/dev/null |
    awk -v id="$bundle_id" 'index($3, id) && $1 != "-" { found = 1 } END { exit !found }'
}

alive=1
for i in $(seq 1 "$WATCH_SECONDS"); do
  sleep 1
  if ! running; then
    echo "  ~${i}s: the app is no longer running"
    alive=0
    break
  fi
done

echo "== Screenshot =="
xcrun simctl io "$udid" screenshot "$OUT_DIR/screenshot.png" >/dev/null 2>&1 || echo "  (no screenshot)"
kill "$log_pid" 2>/dev/null || true

crash=0
if ls "$HOME/Library/Logs/DiagnosticReports/" 2>/dev/null | grep -q "^${executable}"; then
  cp "$HOME/Library/Logs/DiagnosticReports/${executable}"* "$OUT_DIR/" 2>/dev/null || true
  crash=1
fi

xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
if [ "$alive" = 0 ] || [ "$crash" = 1 ]; then
  echo "======== SIMULATOR LOG (tail) ========"
  tail -80 "$OUT_DIR/simulator-log.txt"
  echo "RESULT: the app crashed or stopped within ${WATCH_SECONDS}s." >&2
  exit 1
fi
echo "RESULT: app stayed alive ${WATCH_SECONDS}s — no crash detected."
