#!/usr/bin/env bash
# Regenerates lib/src/proto from res/protos. Requires protoc_plugin 25.1.0 (matches protobuf 6.x): dart pub global activate protoc_plugin 25.1.0;
# and either a working `protoc` or `python -m grpc_tools.protoc` (set PROTOC to override).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PATH:$HOME/.pub-cache/bin"
PROTOC="${PROTOC:-protoc}"
OUT=lib/src/proto
if ! $PROTOC --version >/dev/null 2>&1; then
  echo "protoc not usable; set PROTOC, e.g. PROTOC='python -m grpc_tools.protoc'" >&2; exit 1
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Option-only / descriptor protos are needed on the include path but have no Dart consumers.
# The well-known types (google/protobuf/*.proto) are not generated either: since protoc_plugin
# 22 the generated code imports them from package:protobuf/well_known_types, and the barrel
# lib/src/proto/google/protobuf/index.dart (written below) re-exports them from there.
EXCLUDE='^google/api/(client|field_behavior|routing|launch_stage)\.proto$|^google/protobuf/'
# PROTOC_GEN_DART: path of a protoc-gen-dart executable to use instead of the one on PATH.
PLUGIN=()
if [ -n "${PROTOC_GEN_DART:-}" ]; then PLUGIN=(--plugin="protoc-gen-dart=$PROTOC_GEN_DART"); fi
( cd res/protos && $PROTOC -I. ${PLUGIN[@]+"${PLUGIN[@]}"} $(find . -name '*.proto' | sed 's|^\./||' | sort | grep -Ev "$EXCLUDE") --dart_out=grpc:"$TMP" )
# Keep hand-written barrel files, drop old generated output.
find "$OUT" -name '*.pb*.dart' -delete
cp -R "$TMP"/. "$OUT"/
# The JSON descriptors (*.pbjson.dart) are for reflection, which nothing here uses: they are not
# kept, and the barrels below do not export them.
find "$OUT" -name '*.pbjson.dart' -delete
# Per-directory index.dart barrels.
find "$OUT" -type d | while read -r d; do
  : > "$d/index.dart.tmp"
  for f in $(cd "$d" && ls *.pb*.dart 2>/dev/null | sort); do echo "export '$f';" >> "$d/index.dart.tmp"; done
  [ "$d" = "$OUT" ] && { rm "$d/index.dart.tmp"; continue; }
  mv "$d/index.dart.tmp" "$d/index.dart"
done
# The well-known types that res/protos imports, from package:protobuf.
WKT=package:protobuf/well_known_types/google/protobuf
{
  for t in any duration empty struct timestamp wrappers; do
    echo "export '$WKT/$t.pb.dart';"
    [ "$t" = struct ] && echo "export '$WKT/$t.pbenum.dart';"
  done
} > "$OUT/google/protobuf/index.dart"
# The barrels are hand-written by this script: format them so that the output is what
# `dart format lib` leaves (the generated .pb files are already formatted by the plugin).
find "$OUT" -name index.dart -print0 | xargs -0 dart format >/dev/null
