#!/usr/bin/env bash
# Runs the browser tests of cloud_firestore_dart (test/browser) in Chrome, compiled with
# dart2wasm and with dart2js, against a private Firestore emulator on 127.0.0.1:8090.
#
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
# Environment:
#   TEST_LOG_DIR  where the full outputs go (default: a new temp dir)
#
# Exits non-zero if a run fails.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/cloud_firestore/cloud_firestore_dart"
PORT=8090

COMPILERS=(dart2wasm dart2js)
case "${1:-}" in
  dart2wasm|dart2js) COMPILERS=("$1"); shift;;
  both) shift;;
  -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
esac
if [ $# -eq 0 ]; then set -- test/browser; fi

LOG_DIR="${TEST_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOG_DIR" || exit 2

STARTED=0
if ! curl -s -o /dev/null "http://127.0.0.1:$PORT"; then
  "$ROOT/tool/start_private_emulator.sh" "$PORT" || exit 1
  STARTED=1
fi

failed=0
summary=()
for compiler in "${COMPILERS[@]}"; do
  log="$LOG_DIR/browser_$compiler.log"
  echo "=== $compiler: dart test -j 1 -p chrome -c $compiler $*"
  (cd "$PKG" && dart test -j 1 -p chrome -c "$compiler" "$@") >"$log" 2>&1
  rc=$?
  last=$(tr '\r' '\n' <"$log" | grep -E "^[0-9:]+ \+[0-9]+" | tail -1)
  if [ $rc -eq 0 ]; then
    summary+=("$compiler: PASS (${last#* }) log $log")
  else
    failed=1
    summary+=("$compiler: FAIL (${last#* }) log $log")
    tr '\r' '\n' <"$log" | grep -E "\[E\]$" | sed -E 's/^[0-9:]+ [^:]*: /  failed: /; s/ \[E\]$//' | sort -u
  fi
done

if [ $STARTED -eq 1 ]; then
  "$ROOT/tool/stop_private_emulator.sh" "$PORT"
fi

echo
echo "================ SUMMARY ================"
printf '%s\n' "${summary[@]}"
[ $failed -eq 0 ] && echo "ALL OK" || echo "FAILURES"
exit $failed
