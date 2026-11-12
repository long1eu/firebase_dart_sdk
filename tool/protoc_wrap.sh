#!/bin/sh
# protoc replacement for machines where the Homebrew protoc is broken.
# One-time setup, from the repo root:
#   python3 -m venv .protoc-venv && .protoc-venv/bin/pip install grpcio-tools
# Then: PROTOC="$PWD/tool/protoc_wrap.sh" cloud_firestore/cloud_firestore_dart/tool/gen_protos.sh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="${PROTOC_VENV:-$ROOT/.protoc-venv}"
if [ ! -x "$VENV/bin/python" ]; then
  echo "Missing $VENV; see the setup comment at the top of $0" >&2
  exit 1
fi
exec "$VENV/bin/python" -m grpc_tools.protoc "$@"
