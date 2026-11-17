#!/usr/bin/env bash
# Builds or downloads the files that the browser tests of cloud_firestore_dart load at run
# time and that are not in the repository (all git-ignored). tool/test_browser.sh calls it;
# run it by hand before `dart test -p chrome ...`.
#
# Usage: tool/build_web_test_assets.sh
#
# Add new assets as one more section at the end. Each section must be safe to run again
# (skip the work when the asset is current) and must `exit 1` when the asset cannot be
# trusted; an asset that is merely unavailable is reported and left out, the tests that need
# it skip themselves with a reason.
#
# Assets:
#   test/browser/sqlite3.wasm           the WebAssembly build of SQLite for the persistence
#                                       tests and the SQLite unit tests in a browser
#   test/browser/crash/crash_worker.js  the worker of web_persistence_crash_test.dart
#   test/browser/opfs/sqlite_opfs_worker.js
#                                       the OPFS worker of cloud_firestore_dart_sqlite,
#                                       compiled by its setup_web, for the OPFS storage tests
#   test/browser/opfs/faulty_opfs_worker.js
#                                       the same worker with I/O errors on command
#
# Environment:
#   SQLITE3_WASM  a sqlite3.wasm to use instead of downloading one
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/cloud_firestore/cloud_firestore_dart"

(cd "$PKG" && dart pub get >/dev/null) || exit 1

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# up_to_date <file> <sources...>: whether <file> exists and no source is newer than it.
up_to_date() {
  local target="$1"; shift
  [ -s "$target" ] || return 1
  [ -z "$(find "$@" -newer "$target" -print -quit 2>/dev/null)" ]
}

# --- sqlite3.wasm -------------------------------------------------------------------------
# Of the resolved sqlite3 version. The file is executed in the test browser, so it is only
# accepted with a checksum pinned here: the sha256 of the sqlite3.wasm asset of the release
# "sqlite3-<version>" of simolus3/sqlite3.dart (the release page shows it as the digest of the
# asset). pubspec.lock decides which one CI uses; the other lines let the same tests run on
# another version, for example after `dart pub upgrade sqlite3` or with a dependency override.
# Add a line before moving pubspec.lock to a new version, and run the crash test on it
# (web_persistence_crash_test.dart, dart2js): 3.x lost acknowledged transactions on IndexedDB
# until cloud_firestore_dart_sqlite 0.1.1 waited for its queued writes.
sqlite3_wasm_sha256() {
  case "$1" in
    2.9.4) echo 922a76b182b6af69b030c8e2fdd3283ecc8e827248b20e4b1f3f3db170b52117;;
    3.9.1) echo e7451780e78c56ff864fe9317a0fbcd6aeb2e8de3beba7f5efd963202f7ec3d9;;
  esac
}
SQLITE_PKG="$ROOT/cloud_firestore/cloud_firestore_dart_sqlite"

WASM="$PKG/test/browser/sqlite3.wasm"
SQLITE3_VERSION=$(awk '/^  sqlite3:/{f=1} f && /version:/{gsub(/"/,"",$2); print $2; exit}' "$PKG/pubspec.lock")
SQLITE3_WASM_SHA256=$(sqlite3_wasm_sha256 "$SQLITE3_VERSION")
if [ -n "${SQLITE3_WASM:-}" ]; then
  # A file the caller chose: used as it is.
  cp "$SQLITE3_WASM" "$WASM" || exit 1
  echo "Using $SQLITE3_WASM as sqlite3.wasm (not checked against the pinned checksum)"
else
  if [ -z "$SQLITE3_WASM_SHA256" ]; then
    echo "pubspec.lock has sqlite3 $SQLITE3_VERSION, whose sqlite3.wasm checksum $0 does not pin:"
    echo "add it to sqlite3_wasm_sha256 in the script (or pass a file with SQLITE3_WASM)."
    exit 1
  fi
  if [ ! -s "$WASM" ] || [ "$(sha256_of "$WASM")" != "$SQLITE3_WASM_SHA256" ]; then
    URL="https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$SQLITE3_VERSION/sqlite3.wasm"
    echo "Downloading $URL"
    rm -f "$WASM" "$WASM.version"
    if ! curl -sfL -o "$WASM.tmp" "$URL" || [ ! -s "$WASM.tmp" ]; then
      rm -f "$WASM.tmp"
      echo "Could not download sqlite3.wasm: the tests that need it will be skipped."
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

# --- crash_worker.js ----------------------------------------------------------------------
# The test runner only compiles tests, so the worker of web_persistence_crash_test.dart is
# compiled here. Rebuilt when the worker, the library, the opener it uses
# (cloud_firestore_dart_sqlite) or the resolved dependencies changed.
WORKER="$PKG/test/browser/crash/crash_worker.js"
if up_to_date "$WORKER" "$PKG/test/browser/crash/crash_worker.dart" "$PKG/lib" "$SQLITE_PKG/lib" \
  "$PKG/pubspec.lock" "$ROOT/firebase_core/firebase_app_dart/lib"; then
  :
else
  echo "Compiling test/browser/crash/crash_worker.js"
  COMPILE_LOG="$(mktemp)"
  if ! (cd "$PKG" && dart compile js -O1 -o test/browser/crash/crash_worker.js \
    test/browser/crash/crash_worker.dart) >"$COMPILE_LOG" 2>&1; then
    cat "$COMPILE_LOG"; rm -f "$WORKER" "$COMPILE_LOG"
    echo "Could not compile crash_worker.js"
    exit 1
  fi
  rm -f "$COMPILE_LOG"
fi

# --- sqlite_opfs_worker.js ----------------------------------------------------------------
# The worker of the OPFS storage of cloud_firestore_dart_sqlite, compiled the way its README
# tells apps to (`dart run cloud_firestore_dart_sqlite:setup_web <web dir>`, dart2js -O2).
OPFS_WORKER="$PKG/test/browser/opfs/sqlite_opfs_worker.js"
if up_to_date "$OPFS_WORKER" "$SQLITE_PKG/lib" "$SQLITE_PKG/bin" "$PKG/pubspec.lock"; then
  :
else
  echo "Compiling test/browser/opfs/sqlite_opfs_worker.js"
  COMPILE_LOG="$(mktemp)"
  if ! (cd "$PKG" && dart run cloud_firestore_dart_sqlite:setup_web test/browser/opfs) \
    >"$COMPILE_LOG" 2>&1; then
    cat "$COMPILE_LOG"; rm -f "$OPFS_WORKER" "$COMPILE_LOG"
    echo "Could not compile sqlite_opfs_worker.js"
    exit 1
  fi
  rm -f "$COMPILE_LOG"
fi

# --- faulty_opfs_worker.js ----------------------------------------------------------------
# The OPFS worker with a file system that fails on command (web_persistence_opfs_test.dart).
FAULTY_WORKER="$PKG/test/browser/opfs/faulty_opfs_worker.js"
if up_to_date "$FAULTY_WORKER" "$PKG/test/browser/opfs/faulty_opfs_worker.dart" \
  "$SQLITE_PKG/lib" "$PKG/pubspec.lock"; then
  :
else
  echo "Compiling test/browser/opfs/faulty_opfs_worker.js"
  COMPILE_LOG="$(mktemp)"
  if ! (cd "$PKG" && dart compile js -O1 -o test/browser/opfs/faulty_opfs_worker.js \
    test/browser/opfs/faulty_opfs_worker.dart) >"$COMPILE_LOG" 2>&1; then
    cat "$COMPILE_LOG"; rm -f "$FAULTY_WORKER" "$COMPILE_LOG"
    echo "Could not compile faulty_opfs_worker.js"
    exit 1
  fi
  rm -f "$COMPILE_LOG"
fi
