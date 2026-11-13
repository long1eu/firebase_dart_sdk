#!/usr/bin/env bash
# Builds what the browser tests of cloud_firestore_dart need besides their own compilation by
# `dart test`. Called by tool/test_browser.sh and by CI; safe to run again.
#
# Usage: tool/build_web_test_assets.sh
#
#   test/browser/crash/crash_worker.js   the worker of web_persistence_crash_test.dart, compiled
#                                        with dart2js from crash_worker.dart. It includes
#                                        example/sqlite_database_web.dart, so it is rebuilt every
#                                        time (about 4 s). Not in the repository.
#
# sqlite3.wasm, which the persistence tests also need, is downloaded by tool/test_browser.sh.
#
# Exits non-zero if a build fails.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/cloud_firestore/cloud_firestore_dart"

cd "$PKG" || exit 1
dart pub get >/dev/null || exit 1

echo "Compiling test/browser/crash/crash_worker.js"
if ! dart compile js -O1 -o test/browser/crash/crash_worker.js \
  test/browser/crash/crash_worker.dart >/dev/null; then
  # Shows the errors.
  dart compile js -O1 -o test/browser/crash/crash_worker.js test/browser/crash/crash_worker.dart
  exit 1
fi
