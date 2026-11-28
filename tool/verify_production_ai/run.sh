#!/usr/bin/env bash
# Runs the Firebase AI Logic production verification kit. See README.md next to this file.
# Every check costs money: each runs at least one paid Gemini request.
#
#   tool/verify_production_ai/run.sh --project-id=my-project --app-id=1:123:web:abc --api-key=... --model=gemini-x
#   tool/verify_production_ai/run.sh --yes --project-id=... --app-id=... --api-key=... --model=gemini-x
#   FIREBASE_TEST_PROJECT_ID=... FIREBASE_TEST_APP_ID=... FIREBASE_API_KEY=... \
#     tool/verify_production_ai/run.sh --yes --model=gemini-x --backend=google-ai --backend=agent-platform
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/firebase_ai/firebase_ai_dart"
dart pub get >/dev/null
exec dart run tool/verify_production.dart "$@"
