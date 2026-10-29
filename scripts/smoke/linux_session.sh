#!/usr/bin/env bash
# Runs a command inside a headless Linux desktop session: an Xvfb display, a
# D-Bus session bus and an unlocked GNOME keyring (flutter_secure_storage on
# Linux stores the vault through libsecret, which needs the keyring).
#
#   bash scripts/smoke/linux_session.sh <command> [args...]
set -euo pipefail

export DISPLAY="${DISPLAY_NUMBER:-:99}"
Xvfb "$DISPLAY" -screen 0 1280x900x24 >/dev/null 2>&1 &
xvfb_pid=$!
trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do
  xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
  sleep 0.2
done

exec dbus-run-session -- bash -c '
  # Any non-empty password creates and unlocks the default "login"
  # collection without a prompt (an empty one asks through a dialog).
  printf smoke | gnome-keyring-daemon --unlock --components=secrets >/dev/null
  exec "$@"
' bash "$@"
