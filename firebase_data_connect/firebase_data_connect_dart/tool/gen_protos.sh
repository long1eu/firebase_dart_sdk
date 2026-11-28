#!/usr/bin/env bash
# Regenerates lib/src/proto from res/protos: the message classes only, no service stubs (calls go
# through GrpcCaller with RpcMethod). Requires protoc_plugin 25.1.0 (matches protobuf 6.x):
#   dart pub global activate protoc_plugin 25.1.0
# and either a working `protoc` or `python -m grpc_tools.protoc` (set PROTOC to override). protoc's
# own include directory supplies the well-known types (google/protobuf/*.proto). Running it twice
# leaves `git status` unchanged.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PATH:$HOME/.pub-cache/bin"
PROTOC="${PROTOC:-protoc}"
OUT=lib/src/proto
if ! $PROTOC --version >/dev/null 2>&1; then
  echo "protoc not usable; set PROTOC, e.g. PROTOC='python -m grpc_tools.protoc'" >&2
  exit 1
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# field_behavior.proto only declares an option: it is needed on the include path and has no Dart
# consumer. The well-known types are not generated: the generated code imports them from
# package:protobuf/well_known_types, and the barrel lib/src/proto/google/protobuf/index.dart
# (written below) re-exports them from there.
EXCLUDE='^google/api/field_behavior\.proto$|^google/protobuf/'
# PROTOC_GEN_DART: path of a protoc-gen-dart executable to use instead of the one on PATH.
PLUGIN=()
if [ -n "${PROTOC_GEN_DART:-}" ]; then PLUGIN=(--plugin="protoc-gen-dart=$PROTOC_GEN_DART"); fi
PROTOS=$(cd res/protos && find . -name '*.proto' | sed 's|^\./||' | sort | grep -Ev "$EXCLUDE")
# shellcheck disable=SC2086 # one argument per proto file; the names hold no spaces
(cd res/protos && $PROTOC -I. ${PLUGIN[@]+"${PLUGIN[@]}"} $PROTOS --dart_out="$TMP")
# A first run has no output folder yet.
mkdir -p "$OUT/google/protobuf"
# Keep hand-written barrel files, drop old generated output.
find "$OUT" -name '*.pb*.dart' -delete
cp -R "$TMP"/. "$OUT"/
# The JSON descriptors (*.pbjson.dart) are for reflection, which nothing here uses, and the server
# bases (*.pbserver.dart, written for every service even without the grpc option) are service stubs,
# which nothing calls: neither is kept, and the barrels below do not export them.
find "$OUT" \( -name '*.pbjson.dart' -o -name '*.pbserver.dart' \) -delete
# One index.dart barrel per folder that holds generated files, the root included.
find "$OUT" -type d | sort | while read -r d; do
  files=$(cd "$d" && find . -maxdepth 1 -name '*.pb*.dart' | sed 's|^\./||' | sort)
  [ -z "$files" ] && continue
  for f in $files; do echo "export '$f';"; done >"$d/index.dart"
done
# The well-known types that res/protos imports, from package:protobuf.
WKT=package:protobuf/well_known_types/google/protobuf
{
  for t in duration struct; do
    echo "export '$WKT/$t.pb.dart';"
    [ "$t" = struct ] && echo "export '$WKT/$t.pbenum.dart';"
  done
} >"$OUT/google/protobuf/index.dart"
# The barrels are written by this script: format them so that the output is what `dart format lib`
# leaves (the generated .pb files are already formatted by the plugin).
find "$OUT" -name index.dart -print0 | xargs -0 dart format >/dev/null
