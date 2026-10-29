#!/usr/bin/env bash
# Temporary CI workaround for flutter/flutter#191575: a macOS release build of
# this app dies in gen_snapshot ("Class with illegal cid, full-aot") on the
# FFI structs of Flutter's experimental windowing code (_window_macos.dart),
# which the app never allocates. Marking those structs as VM entry points
# keeps them as regular allocated classes. Patches the CI runner's Flutter SDK
# only; drop this script once Flutter fixes the issue.
#
#   bash scripts/ci/patch_flutter_191575.sh
set -euo pipefail

root="${FLUTTER_ROOT:-$(cd "$(dirname "$(command -v flutter)")/.." && pwd)}"
file="$root/packages/flutter/lib/src/widgets/_window_macos.dart"
[ -f "$file" ] || { echo "No $file: nothing to patch."; exit 0; }
if grep -q 'flutter#191575' "$file"; then
  echo "Already patched: $file"
  exit 0
fi
perl -0pi -e "s/^(final class _\w+ extends Struct \{)/\@pragma('vm:entry-point') \/\/ flutter#191575\n\$1/mg" "$file"
count="$(grep -c 'flutter#191575' "$file" || true)"
echo "Marked $count windowing FFI structs as entry points in $file"
[ "$count" -gt 0 ] || { echo "The struct pattern changed: revisit flutter#191575." >&2; exit 1; }
