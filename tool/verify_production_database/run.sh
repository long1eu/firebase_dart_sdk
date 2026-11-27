#!/usr/bin/env bash
# Runs the Realtime Database production verification kit. See README.md next to this file.
#
#   tool/verify_production_database/run.sh --backend=emulator --create-user
#   tool/verify_production_database/run.sh --backend=production --create-user        # the plan only
#   tool/verify_production_database/run.sh --backend=production --create-user --yes
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/firebase_database/firebase_database_dart"
dart pub get >/dev/null
exec dart run test/production/verify_production.dart "$@"
