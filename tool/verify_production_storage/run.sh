#!/usr/bin/env bash
# Runs the Storage production verification kit. See README.md next to this file.
#
#   FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9399 tool/verify_production_storage/run.sh --backend=emulator
#   tool/verify_production_storage/run.sh --backend=production          # prints what it would do
#   tool/verify_production_storage/run.sh --backend=production --yes
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/firebase_storage/firebase_storage_dart"
dart pub get >/dev/null
exec dart run test/production/verify_production.dart "$@"
