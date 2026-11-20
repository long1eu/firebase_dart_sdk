#!/usr/bin/env bash
# Regenerates lib/src/proto from res/protos, the convention of cloud_firestore_dart/tool/gen_protos.sh. Requires
# protoc_plugin 25.1.0 (matches protobuf 6.x): dart pub global activate protoc_plugin 25.1.0; and a working `protoc`
# (set PROTOC to override, PROTOC_GEN_DART for the plugin executable).
#
# res/protos holds Google's published definitions, unmodified: google/cloud/identitytoolkit/v2 and google/rpc from
# googleapis/googleapis at 15deb874ce84e88e8ec61d05faba8807362bd375 (2026-11-20; the identitytoolkit files last
# changed upstream on 2025-09-17), and google/api and google/protobuf as copies of cloud_firestore_dart/res/protos,
# needed on the include path only.
#
# Only the messages are generated (no gRPC: the package sends them over HTTP with `$alt=proto`). The service
# definitions still produce *.pbserver.dart files, which import the JSON descriptors; both are dropped: nothing here
# uses reflection or a server base class.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PATH:$HOME/.pub-cache/bin"
PROTOC="${PROTOC:-protoc}"
OUT=lib/src/proto
if ! $PROTOC --version >/dev/null 2>&1; then
  echo "protoc not usable; set PROTOC" >&2; exit 1
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# google/api (option definitions) and the well-known types are on the include path only: since protoc_plugin 22 the
# generated code imports the well-known types from package:protobuf/well_known_types.
EXCLUDE='^google/api/|^google/protobuf/'
PLUGIN=()
if [ -n "${PROTOC_GEN_DART:-}" ]; then PLUGIN=(--plugin="protoc-gen-dart=$PROTOC_GEN_DART"); fi
( cd res/protos && $PROTOC -I. ${PLUGIN[@]+"${PLUGIN[@]}"} $(find . -name '*.proto' | sed 's|^\./||' | sort | grep -Ev "$EXCLUDE") --dart_out="$TMP" )
mkdir -p "$OUT"
find "$OUT" -name '*.pb*.dart' -delete
cp -R "$TMP"/. "$OUT"/
find "$OUT" \( -name '*.pbjson.dart' -o -name '*.pbserver.dart' \) -delete
# Per-directory index.dart barrels.
find "$OUT" -type d | while read -r d; do
  [ "$d" = "$OUT" ] && continue
  : > "$d/index.dart.tmp"
  for f in $(cd "$d" && ls *.pb*.dart 2>/dev/null | sort); do echo "export '$f';" >> "$d/index.dart.tmp"; done
  if [ -s "$d/index.dart.tmp" ]; then mv "$d/index.dart.tmp" "$d/index.dart"; else rm "$d/index.dart.tmp"; fi
done
find "$OUT" -name index.dart -print0 | xargs -0 dart format >/dev/null
