#!/usr/bin/env bash
# Runs the cloud_firestore_dart integration tests against the Firestore emulator of one or
# both editions. The emulators must already run (start_emulator.sh,
# start_enterprise_emulator.sh); this script never starts or stops them.
#
# Usage: tool/test_integration.sh [standard|enterprise|both]
#                                 [--transport=grpc|webchannel|webchannel-longpolling]
#                                 [dart test arguments...]
#
#   standard    (default) test/integration against the Standard edition emulator.
#   enterprise  test/integration against the Enterprise edition emulator (tests whose
#               expectations only hold for the Standard edition are skipped, see the
#               "Enterprise edition" section of the package README), then
#               test/integration_enterprise.
#   both        standard, then enterprise.
#
# --transport=webchannel runs the same tests over the web transport (REST and WebChannel,
# through dart:io HTTP) instead of gRPC; the default, grpc, is what the VM uses.
# webchannel-longpolling does the same with the streams in long polling mode.
#
# Extra arguments replace the default test paths and are passed to `dart test`, for example:
#   tool/test_integration.sh enterprise test/integration/firebase/firestore/query_test.dart
#   tool/test_integration.sh standard --transport=webchannel
#
# Environment:
#   FIRESTORE_EMULATOR_HOST             Standard edition emulator (default 127.0.0.1:8080, or
#                                       127.0.0.1:8090 with a webchannel transport: start it
#                                       with tool/start_private_emulator.sh)
#   FIRESTORE_ENTERPRISE_EMULATOR_HOST  Enterprise edition emulator (default 127.0.0.1:8181)
#   TEST_LOG_DIR                        where the full outputs go (default: a new temp dir)
#
# Exits non-zero if a run fails or a needed emulator is not reachable.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/cloud_firestore/cloud_firestore_dart"

MODE="standard"
case "${1:-}" in
  standard|enterprise|both) MODE="$1"; shift;;
  -h|--help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
esac

TRANSPORT="${FIRESTORE_TEST_TRANSPORT:-grpc}"
case "${1:-}" in
  --transport=*) TRANSPORT="${1#--transport=}"; shift;;
esac
case "$TRANSPORT" in
  grpc) TRANSPORT_ENV="FIRESTORE_TEST_TRANSPORT="; SUFFIX="";;
  webchannel) TRANSPORT_ENV="FIRESTORE_TEST_TRANSPORT=webchannel"; SUFFIX="_webchannel";;
  webchannel-longpolling)
    TRANSPORT_ENV="FIRESTORE_TEST_TRANSPORT=webchannel-longpolling"; SUFFIX="_webchannel_longpolling";;
  *) echo "Unknown transport '$TRANSPORT' (grpc, webchannel or webchannel-longpolling)"; exit 2;;
esac

# The web transport opens and drops many HTTP connections, which the shared emulator on 8080
# does not take well (see "Web transport and the emulator" in tool/README.md): by default it
# runs against a private emulator (tool/start_private_emulator.sh, port 8090).
if [ -n "$SUFFIX" ]; then DEFAULT_STANDARD_HOST="127.0.0.1:8090"; else DEFAULT_STANDARD_HOST="127.0.0.1:8080"; fi
STANDARD_HOST="${FIRESTORE_EMULATOR_HOST:-$DEFAULT_STANDARD_HOST}"

ENTERPRISE_HOST="${FIRESTORE_ENTERPRISE_EMULATOR_HOST:-127.0.0.1:8181}"
LOG_DIR="${TEST_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOG_DIR" || exit 2

summary=()
failed=0

reachable() {
  curl -s -o /dev/null "http://$1"
}

# run <label> <log name> <dart test arguments...>; the environment of the run is taken from
# RUN_ENV (an array of NAME=value).
run() {
  local label="$1$([ -n "$SUFFIX" ] && echo " [$TRANSPORT]")" log="$LOG_DIR/$2$SUFFIX.log"
  shift 2
  echo "=== $label: dart test $*"
  (cd "$PKG" && env "${RUN_ENV[@]}" "$TRANSPORT_ENV" dart test "$@") >"$log" 2>&1
  local rc=$?
  # The final progress line looks like "00:05 +42 ~3 -2: Some tests failed."
  local last
  last=$(grep -E "^[0-9:]+ \+[0-9]+" "$log" | tail -1)
  local p s f
  p=$(echo "$last" | sed -nE 's/^[0-9:]+ \+([0-9]+).*/\1/p'); p=${p:-0}
  s=$(echo "$last" | sed -nE 's/.* ~([0-9]+).*/\1/p'); s=${s:-0}
  f=$(echo "$last" | sed -nE 's/.* -([0-9]+).*/\1/p'); f=${f:-0}
  if [ $rc -eq 0 ]; then
    summary+=("$label: PASS ($p passed, $s skipped) log $log")
  else
    failed=1
    summary+=("$label: FAIL ($p passed, $s skipped, $f failed) log $log")
    grep -E "\[E\]$" "$log" | sed -E 's/^[0-9:]+ [^:]*: /  failed: /; s/ \[E\]$//' | sort -u
  fi
}

run_standard() {
  if ! reachable "$STANDARD_HOST"; then
    echo "Standard emulator not reachable on $STANDARD_HOST (tool/start_emulator.sh, or tool/start_private_emulator.sh for a webchannel transport)"
    summary+=("standard: NOT RUN (no emulator on $STANDARD_HOST)"); failed=1; return
  fi
  RUN_ENV=("FIRESTORE_EMULATOR_HOST=$STANDARD_HOST" "FIRESTORE_EMULATOR_EDITION=standard")
  if [ $# -gt 0 ]; then run "standard" standard "$@"; else run "standard" standard test/integration; fi
}

run_enterprise() {
  if ! reachable "$ENTERPRISE_HOST"; then
    echo "Enterprise emulator not reachable on $ENTERPRISE_HOST (tool/start_enterprise_emulator.sh)"
    summary+=("enterprise: NOT RUN (no emulator on $ENTERPRISE_HOST)"); failed=1; return
  fi
  # The standard suite, pointed at the Enterprise edition emulator.
  RUN_ENV=("FIRESTORE_EMULATOR_HOST=$ENTERPRISE_HOST" "FIRESTORE_EMULATOR_EDITION=enterprise"
    "FIRESTORE_ENTERPRISE_EMULATOR_HOST=$ENTERPRISE_HOST")
  if [ $# -gt 0 ]; then
    run "enterprise" enterprise "$@"
    return
  fi
  run "enterprise (standard suite)" enterprise_standard_suite test/integration
  # The tests that need the Enterprise edition. FIRESTORE_EMULATOR_HOST stays what the caller
  # set (the tests that compare the two editions are skipped without it).
  RUN_ENV=("FIRESTORE_ENTERPRISE_EMULATOR_HOST=$ENTERPRISE_HOST" "FIRESTORE_EMULATOR_EDITION=standard")
  run "enterprise (enterprise tests)" enterprise_tests test/integration_enterprise
}

case "$MODE" in
  standard) run_standard "$@";;
  enterprise) run_enterprise "$@";;
  both) run_standard "$@"; run_enterprise "$@";;
esac

echo
echo "================ SUMMARY ================"
printf '%s\n' "${summary[@]}"
[ $failed -eq 0 ] && echo "ALL OK" || echo "FAILURES"
exit $failed
