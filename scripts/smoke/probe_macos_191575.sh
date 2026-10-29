#!/usr/bin/env bash
# Temporary bring-up probe for flutter/flutter#191575: builds a release macOS
# template app that adds one suspect dependency and calls it from main().
#
#   bash scripts/smoke/probe_macos_191575.sh <package|""> <import line> <statement>
set -euo pipefail
package="$1"
import_line="$2"
statement="$3"
dir="$RUNNER_TEMP/probe-${package:-ffi}"
flutter create --platforms=macos "$dir" >/dev/null
cd "$dir"
[ -z "$package" ] || flutter pub add "$package" >/dev/null
cat > lib/main.dart <<DART
import 'package:flutter/material.dart';
$import_line

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  $statement
  runApp(const MaterialApp(home: Text('probe')));
}
DART
flutter build macos --release
