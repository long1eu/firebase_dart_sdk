#!/usr/bin/env bash
# Runs the App Check production verification kit. See README.md next to this file.
#
#   tool/verify_production_app_check/run.sh --project-id=my-project --app-id=1:123:web:abc --api-key=...   # the plan only
#   FIREBASE_APPCHECK_DEBUG_TOKEN=... tool/verify_production_app_check/run.sh --yes --project-id=... --app-id=... --api-key=...
#   FIREBASE_TEST_PROJECT_ID=... FIREBASE_TEST_APP_ID=... FIREBASE_API_KEY=... FIREBASE_APPCHECK_DEBUG_TOKEN=... \
#     tool/verify_production_app_check/run.sh --yes
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/firebase_app_check/firebase_app_check_dart"
dart pub get >/dev/null
exec dart run tool/verify_production.dart "$@"
