#!/usr/bin/env bash
# Runs the Remote Config production verification kit. See README.md next to this file.
#
#   tool/verify_production_remote_config/run.sh --project-id=my-project --app-id=1:123:web:abc --api-key=...   # the plan only
#   tool/verify_production_remote_config/run.sh --yes --project-id=... --app-id=... --api-key=...
#   FIREBASE_TEST_PROJECT_ID=... FIREBASE_TEST_APP_ID=... FIREBASE_API_KEY=... tool/verify_production_remote_config/run.sh --yes
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/firebase_remote_config/firebase_remote_config_dart"
dart pub get >/dev/null
exec dart run tool/verify_production.dart "$@"
