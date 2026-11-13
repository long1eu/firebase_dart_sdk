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
# The persistence tests need the WebAssembly build of SQLite that belongs to the sqlite3 package
# version in pubspec.lock. It is downloaded once from the releases of that package to
# test/browser/sqlite3.wasm (not in the repository). Without it those tests are skipped.
#
# Environment:
#   TEST_LOG_DIR  where the full outputs go (default: a new temp dir)
#   SQLITE3_WASM  a sqlite3.wasm to use instead of downloading one
#
# Exits non-zero if a run fails.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/cloud_firestore/cloud_firestore_dart"
PORT=8090

COMPILERS=(dart2wasm dart2js)
case "${1:-}" in
  dart2wasm|dart2js) COMPILERS=("$1"); shift;;
  both) shift;;
  -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
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

# sqlite3.wasm for the persistence tests, of the resolved sqlite3 version. The file is executed
# in the test browser, so it is only accepted with the checksum pinned here: the sha256 of the
# sqlite3.wasm asset of the release "sqlite3-<version>" of simolus3/sqlite3.dart. When the
# sqlite3 version in pubspec.lock changes, update both lines together.
SQLITE3_WASM_VERSION=2.9.4
SQLITE3_WASM_SHA256=922a76b182b6af69b030c8e2fdd3283ecc8e827248b20e4b1f3f3db170b52117

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

WASM="$PKG/test/browser/sqlite3.wasm"
(cd "$PKG" && dart pub get >/dev/null) || exit 1
SQLITE3_VERSION=$(awk '/^  sqlite3:/{f=1} f && /version:/{gsub(/"/,"",$2); print $2; exit}' "$PKG/pubspec.lock")
if [ -n "${SQLITE3_WASM:-}" ]; then
  # A file the caller chose: used as it is.
  cp "$SQLITE3_WASM" "$WASM" || exit 1
  echo "Using $SQLITE3_WASM as sqlite3.wasm (not checked against the pinned checksum)"
else
  if [ "$SQLITE3_VERSION" != "$SQLITE3_WASM_VERSION" ]; then
    echo "pubspec.lock has sqlite3 $SQLITE3_VERSION but $0 pins the checksum of sqlite3.wasm"
    echo "$SQLITE3_WASM_VERSION: update SQLITE3_WASM_VERSION and SQLITE3_WASM_SHA256 in the script"
    echo "(or pass a file with SQLITE3_WASM)."
    exit 1
  fi
  if [ ! -s "$WASM" ] || [ "$(sha256_of "$WASM")" != "$SQLITE3_WASM_SHA256" ]; then
    URL="https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$SQLITE3_VERSION/sqlite3.wasm"
    echo "Downloading $URL"
    rm -f "$WASM" "$WASM.version"
    if ! curl -sfL -o "$WASM.tmp" "$URL" || [ ! -s "$WASM.tmp" ]; then
      rm -f "$WASM.tmp"
      echo "Could not download sqlite3.wasm: the persistence tests will be skipped."
    elif [ "$(sha256_of "$WASM.tmp")" != "$SQLITE3_WASM_SHA256" ]; then
      echo "sqlite3.wasm from $URL has sha256 $(sha256_of "$WASM.tmp"),"
      echo "expected $SQLITE3_WASM_SHA256. Not using it."
      rm -f "$WASM.tmp"
      exit 1
    else
      mv "$WASM.tmp" "$WASM"; echo "$SQLITE3_VERSION" >"$WASM.version"
    fi
  fi
fi

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
  # The expanded reporter is named explicitly: under GitHub Actions `dart test` switches to
  # its github reporter, whose output the summary below cannot read.
  (cd "$PKG" && dart test --reporter expanded -j 1 -p chrome -c "$compiler" "$@") >"$log" 2>&1
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

echo
echo "================ SUMMARY ================"
printf '%s\n' "${summary[@]}"
[ $failed -eq 0 ] && echo "ALL OK" || echo "FAILURES"
exit $failed
