#!/usr/bin/env bash
# Runs the browser tests of cloud_firestore_dart (test/browser) in Chrome (or the browser in
# TEST_BROWSER), compiled with dart2wasm and with dart2js, against a private Firestore emulator on 127.0.0.1:8090 (or the
# port in FIRESTORE_EMULATOR_PORT).
#
# The browser tests of firebase_storage_dart have their own script: tool/test_browser_storage.sh.
# Usage: tool/test_browser.sh [dart2wasm|dart2js|both] [dart test arguments...]
#
# The emulator is started with tool/start_private_emulator.sh if it does not run yet, and in
# that case stopped again at the end. The shared emulator on 8080 is never used: see "Web
# transport and the emulator" in tool/README.md.
#
# The test files run one after the other (-j 1). Chrome allows six connections per host over
# HTTP/1.1, which is what the emulator speaks, and every client keeps up to two of them open
# for its listen and write streams: test files running side by side starve each other.
#
# The files the tests load at run time and that are not in the repository (sqlite3.wasm for the
# persistence tests, the compiled worker of the crash test) are fetched or built first by
# tool/build_web_test_assets.sh. Without them those tests skip themselves.
#
# Environment:
#   TEST_BROWSER  chrome (default), firefox or safari. Safari needs "Allow remote automation"
#                 (Safari settings, Developer) and only runs dart2js: the runner falls back to
#                 it without a message, so dart2wasm is not run there.
#   TEST_LOG_DIR  where the full outputs go (default: a new temp dir)
#   SQLITE3_WASM  a sqlite3.wasm to use instead of downloading one (build_web_test_assets.sh)
#   FIRESTORE_EMULATOR_PORT  the port of the private emulator (default 8090). The tests read
#                 it from test/browser/emulator_port.txt, which this script writes for the
#                 run (see test/browser/emulator_port.dart); 8080, the shared emulator, is
#                 refused.
#   AUTH_EMULATOR_PORT, AUTH_RULES_EMULATOR_PORT  the Auth emulator and the Firestore emulator
#                 with the rules of tool/auth_emulators/firestore.rules that
#                 web_two_users_test.dart needs (default 9297 and 8297; the Auth emulator's hub
#                 and logging take the next two ports). Started with tool/start_auth_emulators.sh
#                 when they do not run yet, and stopped again at the end; written to
#                 test/browser/auth_emulators.txt. When they cannot be started (no firebase CLI)
#                 that test skips itself.
#
# Exits non-zero if a run fails.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/cloud_firestore/cloud_firestore_dart"
PORT="${FIRESTORE_EMULATOR_PORT:-8090}"
case "$PORT" in
  ''|*[!0-9]*) echo "FIRESTORE_EMULATOR_PORT must be a port number"; exit 2;;
  8080) echo "8080 is the shared emulator; use a private one (start_private_emulator.sh)"; exit 2;;
esac
AUTH_PORT="${AUTH_EMULATOR_PORT:-9297}"
RULES_PORT="${AUTH_RULES_EMULATOR_PORT:-8297}"

BROWSER="${TEST_BROWSER:-chrome}"
case "$BROWSER" in
  chrome|firefox|safari) ;;
  *) echo "TEST_BROWSER must be chrome, firefox or safari"; exit 2;;
esac

COMPILERS=(dart2wasm dart2js)
case "${1:-}" in
  dart2wasm|dart2js) COMPILERS=("$1"); shift;;
  both) shift;;
esac
case "$BROWSER" in
  safari) COMPILERS=(dart2js);;
  -h|--help) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
esac
if [ $# -eq 0 ]; then
  # The files one by one, in the order of their names: the runner loads them in the order
  # given (and in no particular order when it is given the directory), and
  # web_persistence_reload_2_read_test.dart has to be loaded after ..._1_write_test.dart.
  FILES=()
  while IFS= read -r file; do FILES+=("$file"); done \
    < <(cd "$PKG" && ls test/browser/*_test.dart | sort)
  set -- "${FILES[@]}"
fi

LOG_DIR="${TEST_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOG_DIR" || exit 2

# sqlite3.wasm, the crash test worker and whatever else the tests load at run time.
"$ROOT/tool/build_web_test_assets.sh" || exit 1

# The browser cannot read the environment: the tests fetch the port from this file.
PORT_FILE="$PKG/test/browser/emulator_port.txt"
echo "$PORT" >"$PORT_FILE" || exit 2
trap 'rm -f "$PORT_FILE"' EXIT

STARTED=0
if ! curl -s -o /dev/null "http://127.0.0.1:$PORT"; then
  "$ROOT/tool/start_private_emulator.sh" "$PORT" || exit 1
  STARTED=1
fi

# The two emulators of web_two_users_test.dart.
AUTH_FILE="$PKG/test/browser/auth_emulators.txt"
AUTH_STARTED=0
rm -f "$AUTH_FILE"
if curl -s -o /dev/null "http://127.0.0.1:$AUTH_PORT" && curl -s -o /dev/null "http://127.0.0.1:$RULES_PORT"; then
  AUTH_READY=1
elif "$ROOT/tool/start_auth_emulators.sh" "$AUTH_PORT" "$RULES_PORT"; then
  AUTH_READY=1; AUTH_STARTED=1
else
  AUTH_READY=0
  echo "The Auth emulators could not be started: web_two_users_test.dart will be skipped."
fi
if [ "$AUTH_READY" = 1 ]; then
  printf 'auth=127.0.0.1:%s\nfirestore=127.0.0.1:%s\n' "$AUTH_PORT" "$RULES_PORT" >"$AUTH_FILE"
fi
trap 'rm -f "$PORT_FILE" "$AUTH_FILE"' EXIT

failed=0
summary=()
for compiler in "${COMPILERS[@]}"; do
  log="$LOG_DIR/browser_${BROWSER}_$compiler.log"
  echo "=== $compiler: dart test -j 1 -p $BROWSER -c $compiler $*"
  # The expanded reporter is named explicitly: under GitHub Actions `dart test` switches to
  # its github reporter, whose output the summary below cannot read.
  (cd "$PKG" && dart test --reporter expanded -j 1 -p "$BROWSER" -c "$compiler" "$@") >"$log" 2>&1
  rc=$?
  last=$(tr '\r' '\n' <"$log" | grep -E "^[0-9:]+ \+[0-9]+" | tail -1)
  if [ $rc -eq 0 ]; then
    summary+=("$compiler: PASS (${last#* }) log $log")
  else
    failed=1
    summary+=("$compiler: FAIL (${last#* }) log $log")
    "$ROOT/tool/print_test_failures.sh" "$log"
  fi
done

if [ $STARTED -eq 1 ]; then
  "$ROOT/tool/stop_private_emulator.sh" "$PORT"
fi
if [ $AUTH_STARTED -eq 1 ]; then
  "$ROOT/tool/stop_auth_emulators.sh" "$AUTH_PORT" "$RULES_PORT"
fi

echo
echo "================ SUMMARY ================"
printf '%s\n' "${summary[@]}"
[ $failed -eq 0 ] && echo "ALL OK" || echo "FAILURES"
exit $failed
