#!/usr/bin/env bash
# Build, injecting dart-defines (WC_PROJECT_ID, …) from dart_defines.json.
# Usage: scripts/build.sh <target> [args]   e.g. scripts/build.sh apk --release
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter build "$@" --dart-define-from-file=dart_defines.json
