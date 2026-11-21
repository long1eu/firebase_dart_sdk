#!/usr/bin/env bash
# Runs the Storage upload benchmark against a private Storage emulator: starts it on 9480 (hub 9580,
# logging 9680), runs firebase_storage/firebase_storage_dart/benchmark/upload_benchmark.dart with the
# arguments given here, and stops the emulator again, also when the benchmark fails.
#
# Usage: tool/bench_storage.sh [upload_benchmark.dart options]     (see benchmark/README.md)
#   tool/bench_storage.sh --sizes=1,16 --rtt=0,50 --repeats=1
#
# Environment:
#   EMULATOR_DIR   directory for the emulator's pid file, log and configuration (default: a new temp dir)
#   BENCH_PORT     the emulator port (default 9480; hub and logging at +100 and +200)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${BENCH_PORT:-9480}"
EMULATOR_DIR="${EMULATOR_DIR:-$(mktemp -d)}"
export EMULATOR_DIR
export STORAGE_HUB_PORT="$((PORT + 100))"
export STORAGE_LOGGING_PORT="$((PORT + 200))"

cleanup() {
  "$ROOT/tool/stop_storage_emulator.sh" "$PORT" || true
}
trap cleanup EXIT

"$ROOT/tool/start_storage_emulator.sh" "$PORT"
cd "$ROOT/firebase_storage/firebase_storage_dart"
dart pub get >/dev/null
FIREBASE_STORAGE_EMULATOR_HOST="127.0.0.1:$PORT" \
  dart run benchmark/upload_benchmark.dart --backend=emulator "$@"
