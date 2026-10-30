#!/usr/bin/env bash
# Local Xcode 27 check. Creates and later deletes its own simulator; existing
# simulators and their app data are left alone. Run from the repository root.
set -euo pipefail

if [ ! -f pubspec.yaml ] || [ ! -f dart_defines.json ]; then
  echo "Run this script from the repository root." >&2
  exit 2
fi

xcode_version="$(xcodebuild -version)"
xcode_version="${xcode_version%%$'\n'*}"
if [[ ! "$xcode_version" =~ ^Xcode[[:space:]]27([.]|$) ]]; then
  echo "Xcode 27 must be selected with xcode-select; found: $xcode_version" >&2
  exit 2
fi

export OUT_DIR="$(pwd)/build/smoke/xcode27-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
exec > >(tee "$OUT_DIR/run.log") 2>&1

echo "== Source and toolchain =="
git rev-parse HEAD
xcode-select -p
xcodebuild -version
xcrun --sdk iphonesimulator --show-sdk-version
flutter --version

runtime="$(xcrun simctl list runtimes available -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
            and r.get("isAvailable", True)]
if not runtimes:
    sys.exit("no available iOS simulator runtime")
print(max(runtimes, key=lambda r: tuple(map(int, r["version"].split("."))))["identifier"])
')"
device_type="$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
import re
phones = [(int(m.group(1)), d) for d in json.load(sys.stdin)["devicetypes"]
          if (m := re.match(r"iPhone (\d+)", d["name"]))]
if not phones:
    sys.exit("no iPhone simulator device type")
print(max(phones, key=lambda item: item[0])[1]["identifier"])
')"

echo "== Isolated simulator =="
echo "Runtime: $runtime"
echo "Device type: $device_type"
udid="$(xcrun simctl create "WalletDemo-Xcode27-$$" "$device_type" "$runtime")"
cleanup() {
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$udid" >/dev/null 2>&1 || true
}
trap cleanup EXIT
echo "UDID: $udid"

flutter pub get
flutter build ios --simulator --debug --dart-define-from-file=dart_defines.json
bash scripts/smoke/ios_simulator_smoke.sh build/ios/iphonesimulator/Runner.app "$udid"
echo "RESULT: Xcode 27 simulator launch and wallet persistence smoke passed."
echo "Evidence: $OUT_DIR"
