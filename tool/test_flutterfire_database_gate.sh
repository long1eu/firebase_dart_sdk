#!/usr/bin/env bash
# Runs FlutterFire's own firebase_database integration tests (the example's integration_test/, 78
# tests) against firebase_database_dart_platform and the Realtime Database emulator: the acceptance
# gate of the shim.
#
# Usage: FLUTTERFIRE_DIR=<flutterfire checkout> tool/test_flutterfire_database_gate.sh [--dry-run]
#          [--device <id>]
#
#   --dry-run      prints every step and the files it would write, and changes nothing (no temp
#                  directory, no emulator, no flutter command).
#   --device <id>  passed to `flutter test -d` (for example `linux` on a Linux desktop with a
#                  display). Without it the tests run on the host VM (flutter_tester).
#
# What it does:
#   1. checks that FLUTTERFIRE_DIR is a FlutterFire checkout at the pinned commit, with no local
#      change in packages/firebase_database and in the rules file;
#   2. copies the example of packages/firebase_database/firebase_database and FlutterFire's
#      .github/workflows/scripts/database.rules.json into a temporary directory (the checkout is
#      never changed);
#   3. patches the copy:
#      - pubspec.yaml: drops `resolution: workspace`, pins firebase_database 13.1.0, adds
#        firebase_database_dart_platform, and pubspec_overrides.yaml points it, firebase_database_dart
#        and firebase_app_dart at this repository;
#      - lib/firebase_options.dart: a databaseURL in every option set (the refFromURL mismatch test
#        needs one, as FlutterFire's CI fills in) and a Linux case in DefaultFirebaseOptions;
#      - integration_test/gate_test.dart: sets the target platform to Linux (flutter test
#        otherwise reports Android, and useDatabaseEmulator maps localhost to 10.0.2.2 there),
#        calls FirebaseDatabaseDart.use(useDartCore: true), then FlutterFire's e2e main;
#      - a linux/ folder (`flutter create --platforms=linux`), which the example does not have;
#   4. runs `flutter pub get` in the copy;
#   5. starts the Database emulator on port 9000 (the port e2e_test.dart hard-codes) with
#      tool/start_database_emulator.sh, and loads FlutterFire's rules into the namespace of the
#      databaseURL through the emulator's REST API;
#   6. runs `flutter test integration_test/gate_test.dart`, prints the passed, failed and skipped
#      counts, and fails on any failure or on a skip count other than EXPECTED_SKIPS (2: the web
#      only test and the Android only stream test skip themselves on Linux);
#   7. stops the emulator it started; removes the temporary directory when the gate passed and
#      keeps it (path printed) when it failed.
#
# Environment:
#   FLUTTERFIRE_DIR   a FlutterFire checkout with at least packages/firebase_database and .github,
#                     at the pinned commit. For example:
#                       git clone --filter=blob:none --sparse https://github.com/firebase/flutterfire
#                       git -C flutterfire sparse-checkout set packages/firebase_database .github
#                       git -C flutterfire checkout 6a80b1b5eea1ea86ba8c7e7bf2a8525cabb77126
#   FLUTTER           the flutter command (default: flutter on the PATH; the repository pins 3.44.9)
#   EXPECTED_SKIPS    the number of skipped tests that passes the gate (default 2)
set -euo pipefail

PINNED_COMMIT=6a80b1b5eea1ea86ba8c7e7bf2a8525cabb77126
FIREBASE_DATABASE_VERSION=13.1.0
EMULATOR_PORT=9000
DATABASE_URL=https://flutterfire-e2e-tests-default-rtdb.europe-west1.firebasedatabase.app
NAMESPACE=flutterfire-e2e-tests-default-rtdb
EXAMPLE_PATH=packages/firebase_database/firebase_database/example
RULES_PATH=.github/workflows/scripts/database.rules.json

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHIM="$ROOT/firebase_database/firebase_database_dart_platform"
FLUTTER="${FLUTTER:-flutter}"
EXPECTED_SKIPS="${EXPECTED_SKIPS:-2}"
FF="${FLUTTERFIRE_DIR:-}"

DRY_RUN=0
DEVICE=""
while [ $# -gt 0 ]; do
  case "$1" in
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  --device)
    if [ $# -lt 2 ]; then
      echo "--device needs a device id" >&2
      exit 2
    fi
    DEVICE="$2"
    shift 2
    ;;
  -h | --help)
    sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Unknown argument: $1 (see --help)" >&2
    exit 2
    ;;
  esac
done

step() { echo "==> $*"; }

# Runs a command, or only prints it with --dry-run.
run() {
  echo "+ $*"
  if [ "$DRY_RUN" = 0 ]; then
    "$@"
  fi
}

# Writes stdin to the file $1, or only prints it with --dry-run.
write_file() {
  if [ "$DRY_RUN" = 1 ]; then
    echo "+ write $1:"
    sed 's/^/    | /'
  else
    echo "+ write $1"
    cat >"$1"
  fi
}

# Stops on a failed check; with --dry-run reports it and goes on, so every step is printed.
fail_check() {
  if [ "$DRY_RUN" = 1 ]; then
    echo "!! check failed (a real run stops here): $*"
  else
    echo "$*" >&2
    exit 1
  fi
}

# Fails when the file $1 does not contain the fixed string $2 after a patch.
expect_in() {
  if [ "$DRY_RUN" = 0 ] && ! grep -qF -- "$2" "$1"; then
    echo "Patch not applied: '$2' is not in $1 (did the FlutterFire file change?)" >&2
    exit 1
  fi
}

step "1. Checking the FlutterFire checkout"
if [ -z "$FF" ]; then
  fail_check "Set FLUTTERFIRE_DIR to a FlutterFire checkout at $PINNED_COMMIT (see --help)."
elif ! ff_head="$(git -C "$FF" rev-parse HEAD 2>/dev/null)"; then
  fail_check "FLUTTERFIRE_DIR=$FF is not a git checkout."
elif [ "$ff_head" != "$PINNED_COMMIT" ]; then
  fail_check "FLUTTERFIRE_DIR is at $ff_head, not at the pinned $PINNED_COMMIT."
elif [ -n "$(git -C "$FF" status --porcelain -- "$EXAMPLE_PATH" "$RULES_PATH")" ]; then
  fail_check "FLUTTERFIRE_DIR has local changes in $EXAMPLE_PATH or $RULES_PATH."
elif [ ! -d "$FF/$EXAMPLE_PATH/integration_test" ] || [ ! -f "$FF/$RULES_PATH" ]; then
  fail_check "FLUTTERFIRE_DIR lacks $EXAMPLE_PATH or $RULES_PATH (sparse checkout?)."
fi
if [ ! -f "$SHIM/pubspec.yaml" ]; then
  fail_check "No package at $SHIM."
fi
if [ ! -x "$ROOT/tool/start_database_emulator.sh" ]; then
  fail_check "tool/start_database_emulator.sh is missing (it comes with the emulator scripts)."
fi
if [ "$DRY_RUN" = 0 ] && curl -s -o /dev/null "http://127.0.0.1:$EMULATOR_PORT"; then
  fail_check "Port $EMULATOR_PORT is in use; stop what listens there (the e2e suite needs it)."
fi

TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
if [ "$DRY_RUN" = 1 ]; then
  WORK="$TMP_BASE/flutterfire_database_gate.XXXXXX"
else
  WORK="$(mktemp -d "$TMP_BASE/flutterfire_database_gate.XXXXXX")"
fi
APP="$WORK/example"
RULES="$WORK/database.rules.json"
RESULTS="$WORK/results.json"
EMULATOR_STARTED=0
PASSED_GATE=0

cleanup() {
  if [ "$EMULATOR_STARTED" = 1 ]; then
    "$ROOT/tool/stop_database_emulator.sh" "$EMULATOR_PORT" || true
  fi
  if [ "$DRY_RUN" = 1 ]; then
    return
  fi
  if [ "$PASSED_GATE" = 1 ]; then
    if command -v trash >/dev/null; then trash "$WORK"; else rm -r "$WORK"; fi
  else
    echo "The patched copy and the results are kept in $WORK"
  fi
}
trap cleanup EXIT

step "2. Copying the example and the rules into $WORK"
run cp -R "$FF/$EXAMPLE_PATH" "$APP"
run cp "$FF/$RULES_PATH" "$RULES"

step "3. Patching the copy"
run perl -ni -e 'print unless /^resolution:\s*workspace\s*$/' "$APP/pubspec.yaml"
run perl -pi -e "s{^(  firebase_database:).*}{\${1} $FIREBASE_DATABASE_VERSION\n  firebase_database_dart_platform: any}" \
  "$APP/pubspec.yaml"
expect_in "$APP/pubspec.yaml" "firebase_database: $FIREBASE_DATABASE_VERSION"
expect_in "$APP/pubspec.yaml" "firebase_database_dart_platform: any"
write_file "$APP/pubspec_overrides.yaml" <<EOF
dependency_overrides:
  firebase_database_dart_platform:
    path: $SHIM
  firebase_database_dart:
    path: $ROOT/firebase_database/firebase_database_dart
  firebase_app_dart:
    path: $ROOT/firebase_core/firebase_app_dart
EOF

OPTIONS="$APP/lib/firebase_options.dart"
run perl -pi -e "s{^( *)projectId: 'flutterfire-e2e-tests',\$}{\$&\n\${1}databaseURL: '$DATABASE_URL',}" \
  "$OPTIONS"
run perl -pi -e 's{^( *)TargetPlatform\.windows => windows,$}{$&\n${1}TargetPlatform.linux => linux,}' \
  "$OPTIONS"
run perl -pi -e 's{^( *)static const macos = ios;$}{$&\n\n${1}static const linux = windows;}' \
  "$OPTIONS"
expect_in "$OPTIONS" "databaseURL: '$DATABASE_URL',"
expect_in "$OPTIONS" "TargetPlatform.linux => linux,"
expect_in "$OPTIONS" "static const linux = windows;"

write_file "$APP/integration_test/gate_test.dart" <<'EOF'
// The acceptance gate: FlutterFire's e2e suite with firebase_database_dart_platform as the
// implementation of firebase_database. Written by tool/test_flutterfire_database_gate.sh.
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:flutter/foundation.dart';

import 'e2e_test.dart' as e2e;

void main() {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  FirebaseDatabaseDart.use(useDartCore: true);
  e2e.main();
}
EOF

run "$FLUTTER" create --no-pub --platforms=linux --project-name firebase_database_example "$APP"

step "4. Resolving the copy"
run "$FLUTTER" pub get --directory "$APP"

step "5. Starting the Database emulator on $EMULATOR_PORT and loading FlutterFire's rules"
run "$ROOT/tool/start_database_emulator.sh" "$EMULATOR_PORT"
if [ "$DRY_RUN" = 0 ]; then
  EMULATOR_STARTED=1
fi
run curl -sSf -X PUT -H 'Authorization: Bearer owner' --data-binary "@$RULES" \
  "http://127.0.0.1:$EMULATOR_PORT/.settings/rules.json?ns=$NAMESPACE"

step "6. Running FlutterFire's integration tests"
test_args=(test integration_test/gate_test.dart --file-reporter "json:$RESULTS")
if [ -n "$DEVICE" ]; then
  test_args+=(-d "$DEVICE")
fi
echo "+ (cd $APP && $FLUTTER ${test_args[*]})"
if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run: nothing was changed."
  exit 0
fi
status=0
(cd "$APP" && "$FLUTTER" "${test_args[@]}") || status=$?

# The JSON reporter writes one event per line; testDone of a visible test carries its result.
done_lines="$(grep '"type":"testDone"' "$RESULTS" | grep -v '"hidden":true' || true)"
count() { printf '%s\n' "$done_lines" | grep -cE "$1" || true; }
skipped="$(count '"skipped":true')"
failed="$(count '"result":"(failure|error)"')"
passed="$(($(count '"result":"success"') - skipped))"
echo "Passed: $passed, failed: $failed, skipped: $skipped (expected skips: $EXPECTED_SKIPS)"

if [ "$status" != 0 ] || [ "$failed" != 0 ]; then
  echo "The gate failed: flutter test exited with $status, $failed test(s) failed." >&2
  exit 1
fi
if [ "$skipped" != "$EXPECTED_SKIPS" ]; then
  echo "The gate failed: $skipped skipped, expected $EXPECTED_SKIPS (a skip may mean the" >&2
  echo "emulator or a platform condition kept a test from running)." >&2
  exit 1
fi
PASSED_GATE=1
echo "The gate passed."
