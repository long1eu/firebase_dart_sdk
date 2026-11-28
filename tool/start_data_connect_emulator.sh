#!/usr/bin/env bash
# Starts a private Firebase Data Connect emulator (part of firebase-tools; the emulator binary and an
# embedded PGLite database) in the background, on 127.0.0.1:<port>, for project demo-test. It serves
# the fixture of tool/data_connect_emulator/dataconnect: service test-service, connector
# test-connector, location us-central1. One port serves REST, gRPC (plaintext h2c only) and WebSocket.
#
# Usage: tool/start_data_connect_emulator.sh [port]     (default 9499; the CLI's own default is 9399)
#
# The pid file and the log are in EMULATOR_DIR. Stop it with tool/stop_data_connect_emulator.sh [port].
#
# Four ports are used and each must be free before the start:
#   port                      the Data Connect emulator
#   port + 100                the emulator hub        (DATA_CONNECT_HUB_PORT)
#   port + 200                its logging server      (DATA_CONNECT_LOGGING_PORT)
#   port + 300                the embedded PGLite     (DATA_CONNECT_POSTGRES_PORT; the CLI's own is 5432)
#
# Environment:
#   EMULATOR_DIR   directory for the pid file, log and generated firebase.json
#                  (default: <repo>/.emulator)
#   FIREBASE_CLI   the firebase command (default: the first of
#                  $EMULATOR_DIR/node_modules/.bin/firebase,
#                  <repo>/.emulator/node_modules/.bin/firebase (in a git worktree also the
#                  one of the main checkout), and `firebase` on the PATH)
#
# The Data Connect emulator binary (dataconnect-emulator-* in ~/.cache/firebase/emulators) must
# already be downloaded; the script refuses to start otherwise, so that nothing is fetched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT/.emulator}"
FIXTURE="$ROOT/tool/data_connect_emulator/dataconnect"
PORT="${1:-9499}"
HUB_PORT="${DATA_CONNECT_HUB_PORT:-}"
LOGGING_PORT="${DATA_CONNECT_LOGGING_PORT:-}"
POSTGRES_PORT="${DATA_CONNECT_POSTGRES_PORT:-}"
case "$PORT" in
'' | *[!0-9]*)
  echo "Usage: $0 [port] (the port is a number: $PORT)"
  exit 2
  ;;
esac
HUB_PORT="${HUB_PORT:-$((PORT + 100))}"
LOGGING_PORT="${LOGGING_PORT:-$((PORT + 200))}"
POSTGRES_PORT="${POSTGRES_PORT:-$((PORT + 300))}"
for P in "$PORT" "$HUB_PORT" "$LOGGING_PORT" "$POSTGRES_PORT"; do
  case "$P" in
  '' | *[!0-9]*)
    echo "Usage: $0 [port] (ports are numbers: $P)"
    exit 2
    ;;
  8080 | 8181 | 9000 | 9099 | 9199 | 4400 | 4500 | 9399 | 5432)
    echo "$P is a shared or default emulator port; pick another one."
    exit 2
    ;;
  esac
  if [ "$P" -gt 65535 ]; then
    echo "$P is not a port number; pick a lower port."
    exit 2
  fi
done
if [ ! -d "$FIXTURE" ]; then
  echo "The fixture $FIXTURE does not exist."
  exit 2
fi
PID="$EMU/data_connect_emulator_$PORT.pid"
LOG="$EMU/data_connect_emulator_$PORT.log"
CFG="$EMU/data_connect_emulator_$PORT"

if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "Data Connect emulator already running on port $PORT (pid $(cat "$PID"))"
  echo "export FIREBASE_DATA_CONNECT_EMULATOR_HOST=127.0.0.1:$PORT"
  exit 0
fi
# A plain TCP connect: the PGLite port does not speak HTTP.
for P in "$PORT" "$HUB_PORT" "$LOGGING_PORT" "$POSTGRES_PORT"; do
  if (exec 3<>"/dev/tcp/127.0.0.1/$P") 2>/dev/null; then
    echo "Port $P is already in use by a process this script did not start; not starting."
    exit 1
  fi
done

CLI="${FIREBASE_CLI:-}"
if [ -z "$CLI" ]; then
  # The local installs come before the PATH, which may hold a firebase binary for another
  # architecture. In a git worktree <repo> is the worktree; the main checkout is tried too.
  MAIN_ROOT="$(cd "$ROOT" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  MAIN_ROOT="${MAIN_ROOT%/.git}"
  for C in "$EMU/node_modules/.bin/firebase" "$ROOT/.emulator/node_modules/.bin/firebase" \
    ${MAIN_ROOT:+"$MAIN_ROOT/.emulator/node_modules/.bin/firebase"}; do
    if [ -x "$C" ]; then
      CLI="$C"
      break
    fi
  done
  [ -n "$CLI" ] || CLI="$(command -v firebase || true)"
fi
if [ -z "$CLI" ]; then
  echo "The firebase CLI was not found. Install it (mkdir -p .emulator && cd .emulator &&"
  echo "npm init -y && npm install firebase-tools) or set FIREBASE_CLI."
  exit 1
fi
if ! CLI_CHECK="$("$CLI" --version 2>&1)"; then
  echo "The firebase CLI $CLI cannot run:"
  echo "  $CLI_CHECK"
  echo "Install firebase-tools locally or set FIREBASE_CLI to a firebase command that runs here."
  exit 1
fi

if ! ls "$HOME"/.cache/firebase/emulators/dataconnect-emulator-* >/dev/null 2>&1; then
  echo "The Data Connect emulator is not in ~/.cache/firebase/emulators; the CLI would download it."
  echo "Fetch it once with: $CLI setup:emulators:dataconnect"
  exit 1
fi

mkdir -p "$EMU" "$CFG"
# A configuration of its own: only the Data Connect emulator, every port off the CLI defaults, no UI.
cat >"$CFG/firebase.json" <<JSON
{
  "dataconnect": {"source": "$FIXTURE"},
  "emulators": {
    "dataconnect": {"host": "127.0.0.1", "port": $PORT, "postgresPort": $POSTGRES_PORT},
    "hub": {"host": "127.0.0.1", "port": $HUB_PORT},
    "logging": {"host": "127.0.0.1", "port": $LOGGING_PORT},
    "ui": {"enabled": false}
  }
}
JSON
cat >"$CFG/.firebaserc" <<'JSON'
{
  "projects": {"default": "demo-test"}
}
JSON
# exec: the pid file holds the pid of the CLI (node) itself.
(cd "$CFG" && exec nohup "$CLI" emulators:start --only dataconnect --project demo-test \
  --config "$CFG/firebase.json" >"$LOG" 2>&1) &
echo $! >"$PID"
for _ in $(seq 1 120); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT" && break
  kill -0 "$(cat "$PID")" 2>/dev/null || {
    echo "The Data Connect emulator died, see $LOG"
    tail -20 "$LOG"
    rm -f "$PID"
    exit 1
  }
  sleep 1
done
curl -s -o /dev/null "http://127.0.0.1:$PORT" || {
  echo "Timed out waiting for the Data Connect emulator, see $LOG"
  exit 1
}
echo "Data Connect emulator up on 127.0.0.1:$PORT, hub $HUB_PORT, logging $LOGGING_PORT, PGLite $POSTGRES_PORT (pid $(cat "$PID"), log $LOG)"
echo "export FIREBASE_DATA_CONNECT_EMULATOR_HOST=127.0.0.1:$PORT"
