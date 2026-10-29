#!/usr/bin/env bash
# iOS smoke on a fresh simulator: boots the newest available iPhone, checks
# that the built simulator app launches and stays alive, then runs the in-app
# scenario from a clean install.
#
#   bash scripts/smoke/ios_simulator_smoke.sh <path/to/App.app>
set -euo pipefail

app="$1"
udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for device in devices[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
sys.exit("no available iPhone simulator")
')"
echo "== Booting simulator $udid =="
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b

bash scripts/smoke/launch_check_ios_simulator.sh "$app" "$udid"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
xcrun simctl uninstall "$udid" "$bundle_id" || true
flutter test integration_test/smoke_test.dart -d "$udid" \
  --dart-define-from-file=dart_defines.json
