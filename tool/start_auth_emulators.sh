#!/usr/bin/env bash
# Starts the two emulators of the Firebase Auth end-to-end tests, in the background:
#
#   * the Firebase Auth emulator (part of firebase-tools, Node) on 127.0.0.1:<auth port>;
#   * a private Firestore emulator on 127.0.0.1:<firestore port> whose security rules require a
#     signed-in user (tool/auth_emulators/firestore.rules).
#
# The shared emulators (8080, 8181) and their rules are not touched.
#
# Usage: tool/start_auth_emulators.sh [auth port] [firestore port]     (defaults: 9197 8197)
#
# Each emulator has its own pid file and log in EMULATOR_DIR. Stop them with
# tool/stop_auth_emulators.sh [auth port] [firestore port].
#
# Environment:
#   EMULATOR_DIR            directory for the pid files, logs and the generated firebase.json
#                           (default: <repo>/.emulator)
#   FIREBASE_CLI            the firebase command (default: $EMULATOR_DIR/node_modules/.bin/firebase,
#                           else `firebase` on the PATH)
#   FIRESTORE_EMULATOR_JAR  emulator JAR (default: the newest cloud-firestore-emulator-v*.jar in
#                           ~/.cache/firebase/emulators)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT/.emulator}"
AUTH_PORT="${1:-9197}"
FS_PORT="${2:-8197}"
for P in "$AUTH_PORT" "$FS_PORT"; do
  case "$P" in
    ''|*[!0-9]*) echo "Usage: $0 [auth port] [firestore port]"; exit 2;;
    8080|8181|9099) echo "$P is a shared or default emulator port; pick another one."; exit 2;;
  esac
done
RULES="$ROOT/tool/auth_emulators/firestore.rules"
AUTH_PID="$EMU/auth_emulator_$AUTH_PORT.pid"
AUTH_LOG="$EMU/auth_emulator_$AUTH_PORT.log"
AUTH_CFG="$EMU/auth_emulator_$AUTH_PORT"
FS_PID="$EMU/auth_firestore_emulator_$FS_PORT.pid"
FS_LOG="$EMU/auth_firestore_emulator_$FS_PORT.log"

mkdir -p "$EMU" "$AUTH_CFG" || exit 1

running() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

# ---- the Auth emulator ----
if running "$AUTH_PID"; then
  echo "Auth emulator already running on port $AUTH_PORT (pid $(cat "$AUTH_PID"))"
else
  if curl -s -o /dev/null "http://127.0.0.1:$AUTH_PORT"; then
    echo "Port $AUTH_PORT is already in use by a process this script did not start; not starting."
    exit 1
  fi
  CLI="${FIREBASE_CLI:-}"
  if [ -z "$CLI" ]; then
    if [ -x "$EMU/node_modules/.bin/firebase" ]; then
      CLI="$EMU/node_modules/.bin/firebase"
    else
      CLI="$(command -v firebase || true)"
    fi
  fi
  if [ -z "$CLI" ]; then
    echo "The firebase CLI was not found. Install it (mkdir -p .emulator && cd .emulator &&"
    echo "npm init -y && npm install firebase-tools) or set FIREBASE_CLI."
    exit 1
  fi
  # A configuration of its own: only the Auth emulator, with its hub and logging ports next to
  # its own port so that it does not collide with another emulator suite.
  cat >"$AUTH_CFG/firebase.json" <<JSON
{
  "emulators": {
    "auth": {"host": "127.0.0.1", "port": $AUTH_PORT},
    "hub": {"host": "127.0.0.1", "port": $((AUTH_PORT + 1))},
    "logging": {"host": "127.0.0.1", "port": $((AUTH_PORT + 2))},
    "ui": {"enabled": false}
  }
}
JSON
  # exec: the pid file holds the pid of the CLI (node) itself.
  ( cd "$AUTH_CFG" && exec nohup "$CLI" emulators:start --only auth --project demo-test \
      --config "$AUTH_CFG/firebase.json" >"$AUTH_LOG" 2>&1 ) &
  echo $! >"$AUTH_PID"
  for _ in $(seq 1 90); do
    curl -s -o /dev/null "http://127.0.0.1:$AUTH_PORT" && break
    kill -0 "$(cat "$AUTH_PID")" 2>/dev/null || {
      echo "The Auth emulator died, see $AUTH_LOG"; tail -20 "$AUTH_LOG"; rm -f "$AUTH_PID"; exit 1; }
    sleep 1
  done
  curl -s -o /dev/null "http://127.0.0.1:$AUTH_PORT" || {
    echo "Timed out waiting for the Auth emulator, see $AUTH_LOG"; exit 1; }
  echo "Auth emulator up on 127.0.0.1:$AUTH_PORT (pid $(cat "$AUTH_PID"), log $AUTH_LOG)"
fi

# ---- the Firestore emulator with rules that require auth ----
if running "$FS_PID"; then
  echo "Firestore emulator (auth rules) already running on port $FS_PORT (pid $(cat "$FS_PID"))"
else
  if curl -s -o /dev/null "http://127.0.0.1:$FS_PORT"; then
    echo "Port $FS_PORT is already in use by a process this script did not start; not starting."
    exit 1
  fi
  JAR="${FIRESTORE_EMULATOR_JAR:-}"
  if [ -z "$JAR" ]; then
    JAR="$(ls "$HOME"/.cache/firebase/emulators/cloud-firestore-emulator-v*.jar 2>/dev/null \
      | sort -V | tail -1)"
  fi
  if [ -z "$JAR" ] || [ ! -f "$JAR" ]; then
    echo "Firestore emulator JAR not found. Start the standard emulator once (the Firebase CLI"
    echo "downloads the JAR to ~/.cache/firebase/emulators) or set FIRESTORE_EMULATOR_JAR."
    exit 1
  fi
  command -v java >/dev/null 2>&1 || { echo "java not found on PATH"; exit 1; }
  nohup java -Duser.language=en -jar "$JAR" --host 127.0.0.1 --port "$FS_PORT" \
    --database-edition standard --project_id demo-test --rules "$RULES" >"$FS_LOG" 2>&1 &
  echo $! >"$FS_PID"
  for _ in $(seq 1 120); do
    curl -s -o /dev/null "http://127.0.0.1:$FS_PORT" && break
    kill -0 "$(cat "$FS_PID")" 2>/dev/null || {
      echo "The Firestore emulator died, see $FS_LOG"; tail -20 "$FS_LOG"; rm -f "$FS_PID"; exit 1; }
    sleep 1
  done
  curl -s -o /dev/null "http://127.0.0.1:$FS_PORT" || {
    echo "Timed out waiting for the Firestore emulator, see $FS_LOG"; exit 1; }
  echo "Firestore emulator (auth rules) up on 127.0.0.1:$FS_PORT (pid $(cat "$FS_PID"), log $FS_LOG)"
fi

echo "export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:$AUTH_PORT"
echo "export FIRESTORE_AUTH_RULES_EMULATOR_HOST=127.0.0.1:$FS_PORT"
