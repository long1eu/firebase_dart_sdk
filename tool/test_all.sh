#!/usr/bin/env bash
# Runs pub get, analyze (lib) and tests for the two published packages.
# cloud_firestore_dart runs only test/unit (integration needs a live backend).
# Exits non-zero if any step of any package fails.
# Usage: tool/test_all.sh [package-name ...]
#
# Environment:
#   TEST_LOG_DIR  where the outputs of pub get, analyze and test go (default: a new temp dir)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PACKAGES=(
  "firebase_app_dart|firebase_core/firebase_app_dart|"
  "cloud_firestore_dart|cloud_firestore/cloud_firestore_dart|test/unit"
)

summary=()
failed=0
LOG="${TEST_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOG" || exit 2

for entry in "${PACKAGES[@]}"; do
  IFS='|' read -r name dir testpath <<<"$entry"
  if [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qx "$name"; then continue; fi
  echo "=== $name ==="
  cd "$ROOT/$dir" || { summary+=("$name: MISSING DIR"); failed=1; continue; }

  pub=PASS analyze=PASS tests="skipped (no test dir)"

  dart pub get --no-example >"$LOG/$name.pub" 2>&1 || { pub=FAIL; tail -5 "$LOG/$name.pub"; }

  dart analyze lib >"$LOG/$name.an" 2>&1
  if grep -qE "^\s+(error|warning) -" "$LOG/$name.an"; then
    analyze="FAIL ($(grep -cE '^\s+error -' "$LOG/$name.an") errors, $(grep -cE '^\s+warning -' "$LOG/$name.an") warnings)"
    grep -E "^\s+(error|warning) -" "$LOG/$name.an" | head -10
  elif [ $? -ne 0 ] && ! grep -qE "No issues|issues? found" "$LOG/$name.an"; then
    analyze="FAIL (analyzer crashed)"
  else
    analyze="PASS ($(grep -cE '^\s+info -' "$LOG/$name.an") infos)"
  fi

  target="${testpath:-test}"
  if [ -d "$target" ]; then
    # The expanded reporter is named explicitly: under GitHub Actions `dart test` switches
    # to its github reporter, whose output the summary below cannot read.
    dart test --reporter expanded "$target" >"$LOG/$name.test" 2>&1
    rc=$?
    # Final progress line looks like "00:05 +42 -2: ..." / "+44: All tests passed!"
    last=$(grep -E "^[0-9:]+ \+[0-9]+" "$LOG/$name.test" | tail -1)
    p=$(echo "$last" | sed -nE 's/.*\+([0-9]+).*/\1/p'); p=${p:-0}
    f=$(echo "$last" | sed -nE 's/.* -([0-9]+).*/\1/p'); f=${f:-0}
    if [ $rc -eq 0 ]; then tests="PASS ($p passed, $f failed)"; else
      tests="FAIL ($p passed, $f failed)"; "$ROOT/tool/print_test_failures.sh" "$LOG/$name.test"; fi
  fi

  case "$pub$analyze$tests" in *FAIL*) failed=1;; esac
  summary+=("$name: pub get $pub | analyze $analyze | test $tests")
done

echo
echo "================ SUMMARY ================"
printf '%s\n' "${summary[@]}"
[ $failed -eq 0 ] && echo "ALL OK" || echo "FAILURES"
exit $failed
