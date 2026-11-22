#!/usr/bin/env bash
# Runs the browser tests of firebase_storage_dart (test/browser) in Chrome (or the browser in
# TEST_BROWSER), compiled with dart2wasm and with dart2js, against a private Storage emulator on
# 127.0.0.1:9385 (or the port in STORAGE_EMULATOR_PORT).
#
# Usage: tool/test_browser_storage.sh [dart2wasm|dart2js|both] [dart test arguments...]
#
# The emulator is started with tool/start_storage_emulator.sh if it does not run yet, and in that
# case stopped again at the end. The tests read its port from test/browser/emulator_port.txt,
# which this script writes for the run; the CLI's default 9199 and the other shared ports are
# refused by the start script.
#
# Environment:
#   TEST_BROWSER           chrome (default), firefox or safari. Safari only runs dart2js: the
#                          runner falls back to it without a message.
#   STORAGE_EMULATOR_PORT  the port of the private emulator (default 9385; its hub and logging
#                          server take the next two ports)
#   TEST_LOG_DIR           where the full outputs go (default: a new temp dir)
#
# Exits non-zero if a run fails.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/firebase_storage/firebase_storage_dart"
PORT="${STORAGE_EMULATOR_PORT:-9385}"
case "$PORT" in
'' | *[!0-9]*) echo "STORAGE_EMULATOR_PORT must be a port number"; exit 2 ;;
esac

BROWSER="${TEST_BROWSER:-chrome}"
case "$BROWSER" in
chrome | firefox | safari) ;;
*) echo "TEST_BROWSER must be chrome, firefox or safari"; exit 2 ;;
esac

COMPILERS=(dart2wasm dart2js)
case "${1:-}" in
dart2wasm | dart2js) COMPILERS=("$1"); shift ;;
both) shift ;;
-h | --help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
if [ "$BROWSER" = safari ]; then
  COMPILERS=(dart2js)
fi
if [ $# -eq 0 ]; then
  set -- test/browser
fi

LOG_DIR="${TEST_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOG_DIR" || exit 2

PORT_FILE="$PKG/test/browser/emulator_port.txt"
echo "$PORT" >"$PORT_FILE" || exit 2
STARTED=0
cleanup() {
  rm -f "$PORT_FILE"
  if [ "$STARTED" = 1 ]; then
    "$ROOT/tool/stop_storage_emulator.sh" "$PORT"
  fi
}
trap cleanup EXIT

if ! curl -s -o /dev/null "http://127.0.0.1:$PORT"; then
  "$ROOT/tool/start_storage_emulator.sh" "$PORT" || exit 1
  STARTED=1
fi

failed=0
summary=()
for compiler in "${COMPILERS[@]}"; do
  log="$LOG_DIR/browser_storage_${BROWSER}_$compiler.log"
  echo "=== $compiler: dart test -j 1 -p $BROWSER -c $compiler $*"
  (cd "$PKG" && dart test --reporter expanded -j 1 -p "$BROWSER" -c "$compiler" "$@") >"$log" 2>&1
  rc=$?
  last=$(tr '\r' '\n' <"$log" | grep -E "^[0-9:]+ \+[0-9]+" | tail -1)
  if [ $rc -eq 0 ]; then
    summary+=("$compiler: PASS (${last:-no summary line})")
  else
    failed=1
    summary+=("$compiler: FAIL (${last:-no summary line}), see $log")
    tail -30 "$log"
  fi
done

printf '%s\n' "${summary[@]}"
exit $failed
