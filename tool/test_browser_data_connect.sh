#!/usr/bin/env bash
# Runs the tests of firebase_data_connect_dart in headless Chrome, compiled with the compiler in the
# first argument, against a private Data Connect emulator on 9499 (REST only: a browser cannot speak
# gRPC).
#
# Usage: tool/test_browser_data_connect.sh <dart2js|dart2wasm>
#
# Two runs over the whole test tree:
#   1. `dart test -p chrome -c <compiler> -x emulator`: the tests that need no emulator;
#   2. `dart test -p chrome -c <compiler> -t emulator --reporter expanded`: the emulator tests. Its output
#      must show no skip: a skipped emulator test means the emulator address did not reach it, so the
#      script fails.
#
# The script starts the emulator with tool/start_data_connect_emulator.sh (the Data Connect emulator
# must be downloaded: firebase setup:emulators:dataconnect), writes "127.0.0.1:9499" to
# test/browser/emulator_host.txt (git-ignored; the tests read it), and stops the emulator and removes
# the file at the end, also when a run fails. It exits non-zero if any run fails.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <dart2js|dart2wasm>" >&2
  exit 2
fi
COMPILER="$1"
case "$COMPILER" in
dart2js | dart2wasm) ;;
*)
  echo "the compiler must be dart2js or dart2wasm" >&2
  exit 2
  ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/firebase_data_connect/firebase_data_connect_dart"
PORT=9499
HOST_FILE="$PKG/test/browser/emulator_host.txt"
OUT="$(mktemp)"

# shellcheck disable=SC2329 # invoked through the EXIT trap
cleanup() {
  "$ROOT/tool/stop_data_connect_emulator.sh" "$PORT" || true
  rm -f "$HOST_FILE" "$OUT"
}
trap cleanup EXIT

(cd "$PKG" && dart pub get)

"$ROOT/tool/start_data_connect_emulator.sh" "$PORT"
mkdir -p "$PKG/test/browser"
echo "127.0.0.1:$PORT" >"$HOST_FILE"

failed=0
echo "=== firebase_data_connect_dart: dart test -p chrome -c $COMPILER -x emulator"
if ! (cd "$PKG" && dart test --reporter expanded -p chrome -c "$COMPILER" -x emulator); then
  failed=1
fi

echo "=== firebase_data_connect_dart: dart test -p chrome -c $COMPILER -t emulator"
if ! (cd "$PKG" && dart test -p chrome -c "$COMPILER" -t emulator --reporter expanded) | tee "$OUT"; then
  failed=1
fi
if grep -Eq ' ~[0-9]+' "$OUT"; then
  echo "an emulator test was skipped: the emulator address did not reach it" >&2
  failed=1
fi
exit "$failed"
