#!/usr/bin/env bash
# Install the built APK on the attached device/emulator, launch the app, watch
# it, and FAIL if it crashes or never starts — dumping logcat + the crash buffer
# so we can see *why* it died on launch.
#
# Used on-demand by .github/workflows/android-launch-check.yml (NOT part of the
# normal build chain). Also runnable locally against a REAL phone — which is the
# best reproduction for device-specific crashes (e.g. a missing native lib for
# the phone's ABI):
#
#   1. Enable USB debugging on the phone and plug it in (`adb devices`).
#   2. flutter build apk --debug --dart-define-from-file=dart_defines.json
#   3. MODE=debug bash scripts/android_launch_check.sh
#
# Env knobs: MODE (debug|profile|release, default debug), WATCH_SECONDS (20).
set -uo pipefail

MODE="${MODE:-debug}"
PKG="com.example.mobile_wallet_demo"
APK="build/app/outputs/flutter-apk/app-${MODE}.apk"
OUT_DIR="build/launch-logs"
FULL_LOG="$OUT_DIR/logcat-full.txt"
CRASH_LOG="$OUT_DIR/logcat-crash.txt"
WATCH_SECONDS="${WATCH_SECONDS:-20}"

mkdir -p "$OUT_DIR"

echo "== Waiting for device =="
adb wait-for-device
boot=""
for _ in $(seq 1 60); do
  boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
  [ "$boot" = "1" ] && break
  sleep 2
done
echo "sys.boot_completed=$boot"

echo "== Device =="
echo "  api=$(adb shell getprop ro.build.version.sdk | tr -d '\r')  abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')"

if [ ! -f "$APK" ]; then
  echo "APK not found at $APK — build it first (flutter build apk --$MODE)." >&2
  exit 2
fi

echo "== Installing $APK (granting runtime permissions) =="
adb install -r -g "$APK" || { echo "adb install failed" >&2; exit 2; }

echo "== Clearing logcat =="
adb logcat -c 2>/dev/null || true
adb logcat -b crash -c 2>/dev/null || true

echo "== Launching $PKG =="
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true

echo "== Watching for ${WATCH_SECONDS}s =="
crashed=0
ever_started=0
fatal_re="FATAL EXCEPTION|AndroidRuntime: FATAL|has died|signal (11|6)|SIGSEGV|SIGABRT|UnsatisfiedLinkError|beginning of crash"
for i in $(seq 1 "$WATCH_SECONDS"); do
  pid="$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')"
  if [ -n "$pid" ]; then
    ever_started=1
  elif [ "$ever_started" = "1" ]; then
    echo "  ~${i}s: process gone after starting → likely crash"
    crashed=1
    break
  fi
  if adb logcat -b crash -d 2>/dev/null | grep -qE "$fatal_re" \
     || adb logcat -d 2>/dev/null | grep -qE "$fatal_re"; then
    echo "  ~${i}s: fatal marker in logcat"
    crashed=1
    break
  fi
  sleep 1
done

echo "== Dumping logs =="
adb logcat -d -v time > "$FULL_LOG" 2>/dev/null || true
adb logcat -b crash -d -v time > "$OUT_DIR/logcat-crashbuffer.txt" 2>/dev/null || true
grep -nE "FATAL EXCEPTION|AndroidRuntime|$PKG|flutter|UnsatisfiedLinkError|signal (11|6)|SIGSEGV|SIGABRT|has died|Force finishing|ANR in|beginning of crash" \
  "$FULL_LOG" > "$CRASH_LOG" 2>/dev/null || true

echo "================= CRASH BUFFER ================="
cat "$OUT_DIR/logcat-crashbuffer.txt" 2>/dev/null | head -200
echo "============ CRASH / ERROR EXCERPT ============"
if grep -qE "FATAL EXCEPTION|AndroidRuntime" "$FULL_LOG"; then
  awk '/FATAL EXCEPTION|AndroidRuntime/{p=1} p' "$FULL_LOG" | head -150
else
  tail -150 "$CRASH_LOG" 2>/dev/null || true
fi
echo "==============================================="

if [ "$ever_started" = "0" ]; then
  echo "RESULT: app process never appeared — launch failed." >&2
  exit 1
fi
if [ "$crashed" = "1" ]; then
  echo "RESULT: app crashed shortly after launch (see logs above / artifact)." >&2
  exit 1
fi
echo "RESULT: app stayed alive ${WATCH_SECONDS}s — no crash detected."
