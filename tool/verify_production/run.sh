#!/usr/bin/env bash
# Runs the production verification kit. See README.md next to this file.
#
#   tool/verify_production/run.sh --backend=emulator
#   tool/verify_production/run.sh --backend=production          # prints what it would do
#   tool/verify_production/run.sh --backend=production --yes
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/cloud_firestore/cloud_firestore_dart"
dart pub get >/dev/null
exec dart run test/production/verify_production.dart "$@"
