#!/usr/bin/env bash
# Runs pub get, analyze (lib) and tests for the packages of the revival.
# cloud_firestore_dart runs only test/unit (integration needs a live backend). firebase_storage_dart
# runs all of test/: its emulator and production-kit tests skip themselves without
# FIREBASE_STORAGE_EMULATOR_HOST (the CI job "storage" sets it) and test/browser runs only in a browser.
# firebase_auth_secure_storage_dart runs all of test/: its integration tests against the real secret
# store skip themselves without FIREBASE_AUTH_SECURE_STORAGE_INTEGRATION=1.
# firebase_database_dart runs all of test/: its emulator tests skip themselves without
# FIREBASE_DATABASE_EMULATOR_HOST (the CI job "database" sets it) and its browser tests run only in
# a browser. firebase_database_dart_sqlite runs all of test/ (VM only, real SQLite files), with
# test/readme_snippets_test.dart, which compiles the README snippets into test/readme (resolved
# with firebase_auth_providers_dart, cloud_firestore_dart and secure_flow from their sibling
# directories; that generated folder is not formatter-stable: the format check of CI leaves it out).
# firebase_error_reporting_dart runs all of test/ (MockClient, no emulator); the CI job
# "error-reporting-browser" runs it in Chrome as well.
# The example programs in examples/ are analyzed only (their tests need an emulator); select
# them alone with the name "examples", or one with "examples/<name>". The web builds of the
# gallery and their smoke test are not run here: tool/build_gallery.sh, tool/check_gallery.sh and
# tool/smoke_gallery.mjs (the CI job "gallery").
# The Flutter packages (cloud_firestore_dart_flutterfire, cloud_firestore_dart_platform,
# firebase_auth_dart_platform, firebase_storage_dart_platform, firebase_database_dart_platform,
# firebase_auth_secure_storage_flutter) and the Flutter examples need the Flutter SDK and are
# skipped without it; the CI job "flutter" runs them (with FIRESTORE_EMULATOR_HOST,
# FIREBASE_AUTH_EMULATOR_HOST and FIREBASE_DATABASE_EMULATOR_HOST set, so that the emulator tests
# of the platform packages run).
# A Flutter example with a web/index.html is also built for the web, with dart2js
# (`flutter build web`) and with dart2wasm (`flutter build web --wasm`), so that a change that
# breaks web compilation fails here.
# Exits non-zero if any step of any package fails.
# Usage: tool/test_all.sh [package-name ...]
#
# Environment:
#   TEST_LOG_DIR  where the outputs of pub get, analyze and test go (default: a new temp dir)
#   TEST_ALL_REQUIRE_FLUTTER=1  a selected Flutter package or example fails instead of being
#                 skipped when `flutter` is not on the PATH (for the CI job that installs it)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# CI runs cloud_firestore_dart and the others in separate legs (.github/workflows/ci.yml,
# unit-legs and unit-stable-legs): a package added here goes into their `others` leg too.
PACKAGES=(
  "secure_flow|secure_flow/secure_flow|"
  "firebase_app_dart|firebase_core/firebase_app_dart|"
  "firebase_auth_providers_dart|firebase_auth/firebase_auth_providers_dart|"
  "cloud_firestore_dart|cloud_firestore/cloud_firestore_dart|test/unit"
  "cloud_firestore_dart_sqlite|cloud_firestore/cloud_firestore_dart_sqlite|"
  "firebase_admin_dart|firebase_admin/firebase_admin_dart|"
  "firebase_storage_dart|firebase_storage/firebase_storage_dart|"
  "firebase_auth_secure_storage_dart|firebase_auth/firebase_auth_secure_storage_dart|"
  "firebase_database_dart|firebase_database/firebase_database_dart|"
  "firebase_database_dart_sqlite|firebase_database/firebase_database_dart_sqlite|"
  "firebase_error_reporting_dart|firebase_error_reporting/firebase_error_reporting_dart|"
)

summary=()
failed=0

# flutter_skipped <name>: records a Flutter package or example that cannot run here.
flutter_skipped() {
  if [ "${TEST_ALL_REQUIRE_FLUTTER:-}" = 1 ]; then
    summary+=("$1: FAIL (flutter is not on the PATH)")
    failed=1
  else
    summary+=("$1: skipped (needs the Flutter SDK)")
  fi
}

# test_counts <log>: "N passed, N skipped, N failed" from the last progress line of a
# `dart test` or `flutter test` run.
test_counts() {
  local last p s f
  last=$(tr '\r' '\n' <"$1" | grep -E "^[0-9:]+ \+[0-9]+" | tail -1)
  p=$(echo "$last" | sed -nE 's/^[0-9:]+ \+([0-9]+).*/\1/p')
  p=${p:-0}
  s=$(echo "$last" | sed -nE 's/^[0-9:]+ \+[0-9]+ ~([0-9]+).*/\1/p')
  s=${s:-0}
  f=$(echo "$last" | sed -nE 's/^[0-9:]+ \+[0-9]+( ~[0-9]+)? -([0-9]+).*/\2/p')
  f=${f:-0}
  echo "$p passed, $s skipped, $f failed"
}
LOG="${TEST_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOG" || exit 2

for entry in "${PACKAGES[@]}"; do
  IFS='|' read -r name dir testpath <<<"$entry"
  if [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qx "$name"; then continue; fi
  echo "=== $name ==="
  cd "$ROOT/$dir" || {
    summary+=("$name: MISSING DIR")
    failed=1
    continue
  }

  pub=PASS analyze=PASS tests="skipped (no test dir)"

  dart pub get --no-example >"$LOG/$name.pub" 2>&1 || {
    pub=FAIL
    tail -5 "$LOG/$name.pub"
  }

  dart analyze lib >"$LOG/$name.an" 2>&1
  analyze_rc=$?
  if grep -qE "^\s*(error|warning) -" "$LOG/$name.an"; then
    analyze="FAIL ($(grep -cE '^\s*error -' "$LOG/$name.an") errors, $(grep -cE '^\s*warning -' "$LOG/$name.an") warnings)"
    grep -E "^\s*(error|warning) -" "$LOG/$name.an" | head -10
  elif [ "$analyze_rc" -ne 0 ] && ! grep -qE "No issues|issues? found" "$LOG/$name.an"; then
    analyze="FAIL (analyzer crashed)"
  else
    analyze="PASS ($(grep -cE '^\s*info -' "$LOG/$name.an") infos)"
  fi

  target="${testpath:-test}"
  if [ -d "$target" ]; then
    # The expanded reporter is named explicitly: under GitHub Actions `dart test` switches
    # to its github reporter, whose output the summary below cannot read.
    dart test --reporter expanded "$target" >"$LOG/$name.test" 2>&1
    rc=$?
    # "N passed, N skipped, N failed" from the final progress line.
    counts=$(test_counts "$LOG/$name.test")
    if [ $rc -eq 0 ]; then tests="PASS ($counts)"; else
      tests="FAIL ($counts)"
      "$ROOT/tool/print_test_failures.sh" "$LOG/$name.test"
    fi
  fi

  case "$pub$analyze$tests" in *FAIL*) failed=1 ;; esac
  summary+=("$name: pub get $pub | analyze $analyze | test $tests")
done

for pubspec in "$ROOT"/examples/*/pubspec.yaml; do
  [ -f "$pubspec" ] || continue
  dir="$(dirname "$pubspec")"
  name="examples/$(basename "$dir")"
  if [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qxE "examples|$name"; then continue; fi
  log="$LOG/examples_$(basename "$dir")"
  echo "=== $name ==="
  tool=dart
  if grep -qE '^\s*sdk:\s*flutter\s*$' "$pubspec"; then
    # A Flutter example resolves only with the Flutter SDK.
    if ! command -v flutter >/dev/null 2>&1; then
      flutter_skipped "$name"
      continue
    fi
    tool=flutter
  fi
  pub=PASS analyze=PASS
  (cd "$dir" && $tool pub get >"$log.pub" 2>&1) || {
    pub=FAIL
    tail -5 "$log.pub"
  }
  # `flutter analyze` prints its issues as "info • ..." and exits non-zero on any issue.
  (cd "$dir" && $tool analyze >"$log.an" 2>&1)
  rc=$?
  if grep -qE "^\s*(error|warning|info) (-|•)" "$log.an"; then
    analyze="FAIL ($(grep -cE '^\s*(error|warning|info) (-|•)' "$log.an") issues)"
    grep -E "^\s*(error|warning|info) (-|•)" "$log.an" | head -10
  elif [ $rc -ne 0 ] || ! grep -q "No issues found" "$log.an"; then
    analyze="FAIL (analyzer crashed)"
    tail -10 "$log.an"
  fi
  web=""
  if [ "$tool" = flutter ] && [ -f "$dir/web/index.html" ]; then
    js=PASS wasm=PASS
    (cd "$dir" && flutter build web >"$log.web" 2>&1) || {
      js=FAIL
      tail -10 "$log.web"
    }
    (cd "$dir" && flutter build web --wasm >"$log.wasm" 2>&1) || {
      wasm=FAIL
      tail -10 "$log.wasm"
    }
    web=" | build web $js | build web --wasm $wasm"
  fi
  case "$pub$analyze$web" in *FAIL*) failed=1 ;; esac
  summary+=("$name: pub get $pub | analyze $analyze$web | test not run (needs an emulator)")
done

# The Flutter packages: `dart test` cannot load flutter_test. The emulator tests of
# cloud_firestore_dart_platform run only when FIRESTORE_EMULATOR_HOST is set, those of
# firebase_auth_dart_platform only when FIREBASE_AUTH_EMULATOR_HOST is set, those of
# firebase_database_dart_platform only when FIREBASE_DATABASE_EMULATOR_HOST is set;
# firebase_auth_secure_storage_flutter has unit tests only (a fake of the plugin's channel).
for entry in "cloud_firestore_dart_flutterfire|cloud_firestore/cloud_firestore_dart_flutterfire" \
  "cloud_firestore_dart_platform|cloud_firestore/cloud_firestore_dart_platform" \
  "firebase_auth_dart_platform|firebase_auth/firebase_auth_dart_platform" \
  "firebase_storage_dart_platform|firebase_storage/firebase_storage_dart_platform" \
  "firebase_database_dart_platform|firebase_database/firebase_database_dart_platform" \
  "firebase_auth_secure_storage_flutter|firebase_auth/firebase_auth_secure_storage_flutter"; do
  IFS='|' read -r name dir <<<"$entry"
  if [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qx "$name"; then continue; fi
  echo "=== $name ==="
  if ! command -v flutter >/dev/null 2>&1; then
    flutter_skipped "$name"
    continue
  fi
  dir="$ROOT/$dir"
  pub=PASS analyze=PASS
  (cd "$dir" && flutter pub get >"$LOG/$name.pub" 2>&1) || {
    pub=FAIL
    tail -5 "$LOG/$name.pub"
  }
  (cd "$dir" && flutter analyze >"$LOG/$name.an" 2>&1) || {
    analyze=FAIL
    tail -10 "$LOG/$name.an"
  }
  # The expanded reporter: one progress line per event, which test_counts reads.
  if (cd "$dir" && flutter test --reporter expanded >"$LOG/$name.test" 2>&1); then
    tests="PASS ($(test_counts "$LOG/$name.test"))"
  else
    tests="FAIL ($(test_counts "$LOG/$name.test"))"
    tail -20 "$LOG/$name.test"
  fi
  case "$pub$analyze$tests" in *FAIL*) failed=1 ;; esac
  summary+=("$name: pub get $pub | analyze $analyze | test $tests")
done

echo
echo "================ SUMMARY ================"
printf '%s\n' "${summary[@]}"
[ $failed -eq 0 ] && echo "ALL OK" || echo "FAILURES"
exit $failed
