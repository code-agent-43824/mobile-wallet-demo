#!/usr/bin/env bash
# Android smoke on a booted emulator: the exact release APK must launch and
# stay alive, then the in-app scenario runs from a clean install.
#
#   bash scripts/smoke/android_smoke.sh <path/to/app-release.apk>
set -euo pipefail

apk="$1"
OUT_DIR="${OUT_DIR:-build/smoke}" WATCH_SECONDS="${WATCH_SECONDS:-30}" APK="$apk" \
  bash scripts/android_launch_check.sh
adb uninstall com.example.mobile_wallet_demo >/dev/null 2>&1 || true
flutter test integration_test/smoke_test.dart \
  -d "${ANDROID_SERIAL:-emulator-5554}" \
  --dart-define-from-file=dart_defines.json
