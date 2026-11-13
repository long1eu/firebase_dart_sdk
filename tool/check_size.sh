#!/usr/bin/env bash
# Compiles the two sample applications of tool/size (the same program with Firestore Lite and
# with the main library) with `dart compile js -O2` and prints their sizes, raw and gzipped.
# Fails if the lite application contains code of the local store, the sync engine, the remote
# store or the WebChannel transport (read from the compiler's --dump-info output), or if it
# grew past the budget stated in tool/size/check_size.dart.
#
# Usage: tool/check_size.sh
#
# Environment:
#   SIZE_OUT_DIR  where the compiled programs and the dumps go (default: a new temp dir)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/cloud_firestore/cloud_firestore_dart"
OUT="${SIZE_OUT_DIR:-$(mktemp -d)}"

(cd "$PKG" && dart pub get >/dev/null) || exit 2
dart "$ROOT/tool/size/check_size.dart" "$PKG/.dart_tool/package_config.json" "$OUT"
rc=$?
echo "Output in $OUT"
exit $rc
