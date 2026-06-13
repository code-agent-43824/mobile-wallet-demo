#!/usr/bin/env bash
# Run the app, injecting dart-defines (WC_PROJECT_ID, …) from dart_defines.json.
# Usage: scripts/run.sh [extra `flutter run` args]   e.g. scripts/run.sh -d windows
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter run --dart-define-from-file=dart_defines.json "$@"
