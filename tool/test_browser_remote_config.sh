#!/usr/bin/env bash
# Runs the browser tests of firebase_installations_dart and firebase_remote_config_dart (test/browser of
# each) in headless Chrome, compiled with the compiler in the first argument, against the fake server of
# tool/remote_config_fake_server.dart.
#
# Usage: tool/test_browser_remote_config.sh <dart2js|dart2wasm>
#
# The script starts the fake server on a port the system picks, writes that port to
# test/browser/server_port.txt in both packages (git-ignored; the tests read it) and stops the server and
# removes the files at the end, also when a run fails. It exits non-zero if any run fails.
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
PACKAGES=(
  "$ROOT/firebase_installations/firebase_installations_dart"
  "$ROOT/firebase_remote_config/firebase_remote_config_dart"
)

SERVER_OUT="$(mktemp)"
SERVER_PID=""
# shellcheck disable=SC2329 # invoked through the EXIT trap
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  for pkg in "${PACKAGES[@]}"; do
    rm -f "$pkg/test/browser/server_port.txt"
  done
  rm -f "$SERVER_OUT"
}
trap cleanup EXIT

for pkg in "${PACKAGES[@]}"; do
  (cd "$pkg" && dart pub get)
done

dart run "$ROOT/tool/remote_config_fake_server.dart" >"$SERVER_OUT" &
SERVER_PID=$!

PORT=""
for _ in $(seq 1 100); do
  PORT="$(head -n 1 "$SERVER_OUT" 2>/dev/null || true)"
  case "$PORT" in
  '' | *[!0-9]*) PORT="" ;;
  *) break ;;
  esac
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "the fake server exited before it printed its port" >&2
    exit 1
  fi
  sleep 0.2
done
if [ -z "$PORT" ]; then
  echo "the fake server did not print its port within 20 seconds" >&2
  exit 1
fi
echo "fake server on 127.0.0.1:$PORT"

for pkg in "${PACKAGES[@]}"; do
  mkdir -p "$pkg/test/browser"
  echo "$PORT" >"$pkg/test/browser/server_port.txt"
done

failed=0
for pkg in "${PACKAGES[@]}"; do
  echo "=== $(basename "$pkg"): dart test -p chrome -c $COMPILER -j 1 test/browser"
  if ! (cd "$pkg" && dart test --reporter expanded -p chrome -c "$COMPILER" -j 1 test/browser); then
    failed=1
  fi
done
exit "$failed"
