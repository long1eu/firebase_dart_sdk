#!/usr/bin/env bash
# Regenerates lib/src/proto from res/protos. Requires protoc_plugin 21.1.2 (matches protobuf 3.x): dart pub global activate protoc_plugin 21.1.2;
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
EXCLUDE='^google/api/(client|field_behavior|routing|launch_stage)\.proto$|^google/protobuf/descriptor\.proto$'
( cd res/protos && $PROTOC -I. $(find . -name '*.proto' | sed 's|^\./||' | sort | grep -Ev "$EXCLUDE") --dart_out=grpc:"$TMP" )
# Keep hand-written barrel files, drop old generated output.
find "$OUT" -name '*.pb*.dart' -delete
cp -R "$TMP"/. "$OUT"/
# Per-directory index.dart barrels.
find "$OUT" -type d | while read -r d; do
  : > "$d/index.dart.tmp"
  for f in $(cd "$d" && ls *.pb*.dart 2>/dev/null | sort); do echo "export '$f';" >> "$d/index.dart.tmp"; done
  [ "$d" = "$OUT" ] && { rm "$d/index.dart.tmp"; continue; }
  mv "$d/index.dart.tmp" "$d/index.dart"
done
