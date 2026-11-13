#!/usr/bin/env bash
# Runs the unit tests of the SQLite layer of cloud_firestore_dart in Chrome, compiled with
# dart2js: test/unit/firebase/firestore/local/sqlite_*_test.dart on the WebAssembly build of
# SQLite (test/util/sqlite3_database_web.dart). No emulator is needed.
#
# Usage: tool/test_unit_browser.sh [dart test arguments...]
#
# Extra arguments replace the default list of files. The files below are left out of the
# default list, each for the reason next to it; they all pass on the VM.
#
# Environment:
#   TEST_LOG_DIR  where the full output goes (default: a new temp dir)
#
# Exits non-zero if the run fails.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/cloud_firestore/cloud_firestore_dart"
DIR=test/unit/firebase/firestore/local

# file name|reason
EXCLUDED=(
  "sqlite_schema_test.dart|imports dart:io (database files on disk): does not compile for the web"
  "sqlite_schema_extra_test.dart|imports dart:io (database files on disk): does not compile for the web"
  "sqlite_field_index_manager_test.dart|testAdvancedQueries fails with dart2js: JavaScript numbers do not tell the integer 0 from the double 0.0, which the test orders by"
  "sqlite_lru_garbage_collector_test.dart|testGetsSize fails with dart2js: the in-memory file system of the page does not grow with the data like a file does"
)

case "${1:-}" in
  -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
esac

LOG_DIR="${TEST_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOG_DIR" || exit 2
LOG="$LOG_DIR/unit_browser_dart2js.log"

# sqlite3.wasm (and the other files browser tests load at run time).
"$ROOT/tool/build_web_test_assets.sh" || exit 1

if [ $# -eq 0 ]; then
  FILES=()
  while IFS= read -r file; do
    name="$(basename "$file")"
    skip=""
    for entry in "${EXCLUDED[@]}"; do
      if [ "${entry%%|*}" = "$name" ]; then skip="${entry#*|}"; fi
    done
    if [ -n "$skip" ]; then echo "Not run: $name ($skip)"; else FILES+=("$file"); fi
  done < <(cd "$PKG" && ls "$DIR"/sqlite_*_test.dart | sort)
  set -- "${FILES[@]}"
fi

echo "=== dart2js: dart test -p chrome -c dart2js ($# files)"
# The expanded reporter is named explicitly: under GitHub Actions `dart test` switches to its
# github reporter, whose output the summary below cannot read.
(cd "$PKG" && dart test --reporter expanded -p chrome -c dart2js "$@") >"$LOG" 2>&1
rc=$?
last=$(tr '\r' '\n' <"$LOG" | grep -E "^[0-9:]+ \+[0-9]+" | tail -1)
echo
echo "================ SUMMARY ================"
if [ $rc -eq 0 ]; then
  echo "SQLite unit tests in Chrome (dart2js): PASS (${last#* }) log $LOG"
  echo "ALL OK"
else
  "$ROOT/tool/print_test_failures.sh" "$LOG"
  echo "SQLite unit tests in Chrome (dart2js): FAIL (${last#* }) log $LOG"
  echo "FAILURES"
fi
exit $rc
