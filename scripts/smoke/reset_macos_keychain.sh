#!/usr/bin/env bash
# Deletes the vault items flutter_secure_storage keeps in the macOS login
# keychain (service "flutter_secure_storage_service", AppleOptions'
# defaultAccountName). macOS ties such an item to the signature of the app
# that wrote it, so after the release build has run, a differently signed
# build (the scenario's debug build) reading it would wait on an access
# prompt that nobody answers on a CI runner.
set -uo pipefail
removed=0
while security delete-generic-password -s flutter_secure_storage_service >/dev/null 2>&1; do
  removed=$((removed + 1))
  [ "$removed" -lt 100 ] || break
done
echo "Removed $removed flutter_secure_storage keychain item(s)."
