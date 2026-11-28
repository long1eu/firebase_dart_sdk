#!/usr/bin/env bash
# Runs the Data Connect production verification kit. See README.md next to this file.
#
#   tool/verify_production_data_connect/run.sh --stage a --project-id=my-project --app-id=1:123:web:abc --api-key=...   # the plan only
#   tool/verify_production_data_connect/run.sh --yes --stage a --project-id=... --app-id=... --api-key=... \
#     --location=us-central1 --service=my-service --connector=my-connector
#   FIREBASE_TEST_PROJECT_ID=... FIREBASE_TEST_APP_ID=... FIREBASE_API_KEY=... tool/verify_production_data_connect/run.sh --yes --stage b
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/firebase_data_connect/firebase_data_connect_dart"
dart pub get >/dev/null
exec dart run tool/verify_production.dart "$@"
