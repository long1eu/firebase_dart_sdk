#!/usr/bin/env bash
# Starts the Auth and Firestore emulators (project demo-two-users, the rules of firestore.rules),
# builds the page and serves it on another port, so that every request of the page is a
# cross-origin request (CORS is part of what it shows). Ctrl-C stops what it started.
#
# Usage: ./run.sh [--js] [--no-build]
#
#   --js        build with dart2js (flutter build web) instead of dart2wasm; the build for a browser
#               without WebAssembly garbage collection. Without it the build is dart2wasm
#               (flutter build web --wasm), which also writes a dart2js fallback that
#               Flutter's loader picks by itself.
#   --no-build  serve the build that is there
#
# Environment (the defaults avoid the emulators' own default ports 8080, 9099, 4400, 4500):
#   AUTH_PORT       the Auth emulator (default 9201; its hub and logging take the next two)
#   FIRESTORE_PORT  the Firestore emulator (default 8202; its websocket takes 8204)
#   WEB_PORT        the page (default 8203)
#   FIREBASE_CLI    the firebase command (default: the copy that tool/README.md of the
#                   repository installs in .emulator/, else `firebase` on the PATH)
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
AUTH_PORT="${AUTH_PORT:-9201}"
FIRESTORE_PORT="${FIRESTORE_PORT:-8202}"
WEB_PORT="${WEB_PORT:-8203}"
PROJECT=demo-two-users
WASM=1
BUILD=1
for arg in "$@"; do
  case "$arg" in
    --js) WASM=0;;
    --wasm) WASM=1;;
    --no-build) BUILD=0;;
    *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2;;
  esac
done

# sqlite3.wasm of the sqlite3 version in pubspec.lock, which pubspec.yaml pins.
SQLITE3_VERSION=3.3.4
SQLITE3_WASM_SHA256=cfab48c6bbb718552ec19bc4f1365e19185311b72e4739cc19ef7333758304d3

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# A local install first: a firebase on the PATH may be built for another CPU.
CLI="${FIREBASE_CLI:-}"
if [ -z "$CLI" ]; then
  MAIN="$(cd "$DIR" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  for C in "$DIR/../../.emulator/node_modules/.bin/firebase" \
      ${MAIN:+"${MAIN%/.git}/.emulator/node_modules/.bin/firebase"} "$(command -v firebase || true)"; do
    if [ -n "$C" ] && [ -x "$C" ] && "$C" --version >/dev/null 2>&1; then CLI="$C"; break; fi
  done
fi
[ -n "$CLI" ] || { echo "The firebase CLI was not found (npm install -g firebase-tools, or set FIREBASE_CLI)."; exit 1; }

for P in "$AUTH_PORT" "$((AUTH_PORT + 1))" "$((AUTH_PORT + 2))" "$FIRESTORE_PORT" \
    "$((FIRESTORE_PORT + 2))" "$WEB_PORT"; do
  if curl -s -o /dev/null "http://127.0.0.1:$P"; then
    echo "Port $P is in use; set AUTH_PORT, FIRESTORE_PORT or WEB_PORT."; exit 1
  fi
done

cd "$DIR" || exit 1
mkdir -p build/emulators
cat >build/emulators/firebase.json <<JSON
{
  "firestore": {"rules": "$DIR/firestore.rules"},
  "emulators": {
    "auth": {"host": "127.0.0.1", "port": $AUTH_PORT},
    "firestore": {"host": "127.0.0.1", "port": $FIRESTORE_PORT, "websocketPort": $((FIRESTORE_PORT + 2))},
    "hub": {"host": "127.0.0.1", "port": $((AUTH_PORT + 1))},
    "logging": {"host": "127.0.0.1", "port": $((AUTH_PORT + 2))},
    "ui": {"enabled": false}
  }
}
JSON

PIDS=()
cleanup() {
  # The firebase CLI stops its emulators on SIGINT; the file server on SIGTERM.
  [ -n "${PIDS[0]:-}" ] && kill -INT "${PIDS[0]}" 2>/dev/null
  [ -n "${PIDS[1]:-}" ] && kill -TERM "${PIDS[1]}" 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM

( cd build/emulators && exec "$CLI" emulators:start --only auth,firestore --project "$PROJECT" \
    --config firebase.json >emulators.log 2>&1 ) &
PIDS+=($!)

if [ "$BUILD" = 1 ]; then
  if [ ! -s web/sqlite3.wasm ] || [ "$(sha256_of web/sqlite3.wasm)" != "$SQLITE3_WASM_SHA256" ]; then
    URL="https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$SQLITE3_VERSION/sqlite3.wasm"
    echo "Downloading $URL"
    curl -sfL -o web/sqlite3.wasm.tmp "$URL" || { echo "Download failed"; exit 1; }
    if [ "$(sha256_of web/sqlite3.wasm.tmp)" != "$SQLITE3_WASM_SHA256" ]; then
      echo "sqlite3.wasm has an unexpected sha256; not using it."; rm -f web/sqlite3.wasm.tmp; exit 1
    fi
    mv web/sqlite3.wasm.tmp web/sqlite3.wasm
  fi
  FLAGS=(--dart-define="FIRESTORE_EMULATOR=127.0.0.1:$FIRESTORE_PORT"
         --dart-define="AUTH_EMULATOR=127.0.0.1:$AUTH_PORT")
  [ "$WASM" = 1 ] && FLAGS+=(--wasm)
  flutter build web "${FLAGS[@]}" || exit 1
fi

for _ in $(seq 1 120); do
  curl -s -o /dev/null "http://127.0.0.1:$AUTH_PORT" && curl -s -o /dev/null "http://127.0.0.1:$FIRESTORE_PORT" && break
  kill -0 "${PIDS[0]}" 2>/dev/null || { echo "The emulators stopped:"; tail -20 build/emulators/emulators.log; exit 1; }
  sleep 1
done

dart run tool/serve.dart "$WEB_PORT" build/web &
PIDS+=($!)
echo
echo "Auth emulator      http://127.0.0.1:$AUTH_PORT"
echo "Firestore emulator http://127.0.0.1:$FIRESTORE_PORT  (rules: firestore.rules)"
echo "The page           http://127.0.0.1:$WEB_PORT/   and   http://127.0.0.1:$WEB_PORT/?cache=sqlite"
echo "Ctrl-C stops all three."
wait
