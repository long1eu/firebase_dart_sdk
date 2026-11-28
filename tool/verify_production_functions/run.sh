#!/usr/bin/env bash
# Runs the Functions production verification kit. See README.md next to this file.
#
#   FIREBASE_FUNCTIONS_EMULATOR_HOST=127.0.0.1:9501 tool/verify_production_functions/run.sh --backend=emulator
#   tool/verify_production_functions/run.sh --backend=production          # prints what it would do
#   tool/verify_production_functions/run.sh --backend=production --yes
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/cloud_functions/cloud_functions_dart"
dart pub get >/dev/null
exec dart run tool/verify_production.dart "$@"
