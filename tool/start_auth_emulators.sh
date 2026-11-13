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
#   FIREBASE_CLI            the firebase command (default: the first of
#                           $EMULATOR_DIR/node_modules/.bin/firebase,
#                           <repo>/.emulator/node_modules/.bin/firebase (in a git worktree also the
#                           one of the main checkout), and `firebase` on the PATH)
#   FIRESTORE_EMULATOR_JAR  emulator JAR (default: the newest cloud-firestore-emulator-v*.jar in
#                           ~/.cache/firebase/emulators)
#   AUTH_HUB_PORT           port of the emulator hub that the firebase CLI starts with the Auth
#                           emulator (default: auth port + 1; the CLI's own default is 4400)
#   AUTH_LOGGING_PORT       port of its logging server (default: auth port + 2; CLI default 4500)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT/.emulator}"
AUTH_PORT="${1:-9197}"
FS_PORT="${2:-8197}"
case "$AUTH_PORT" in
  ''|*[!0-9]*) echo "Usage: $0 [auth port] [firestore port]"; exit 2;;
esac
HUB_PORT="${AUTH_HUB_PORT:-$((AUTH_PORT + 1))}"
LOGGING_PORT="${AUTH_LOGGING_PORT:-$((AUTH_PORT + 2))}"
for P in "$AUTH_PORT" "$FS_PORT" "$HUB_PORT" "$LOGGING_PORT"; do
  case "$P" in
    ''|*[!0-9]*) echo "Usage: $0 [auth port] [firestore port] (ports are numbers: $P)"; exit 2;;
    8080|8181|9099|4400|4500) echo "$P is a shared or default emulator port; pick another one."; exit 2;;
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
  for P in "$AUTH_PORT" "$HUB_PORT" "$LOGGING_PORT"; do
    if curl -s -o /dev/null "http://127.0.0.1:$P"; then
      echo "Port $P is already in use by a process this script did not start; not starting."
      exit 1
    fi
  done
  CLI="${FIREBASE_CLI:-}"
  if [ -z "$CLI" ]; then
    # The local installs come before the PATH, which may hold a firebase binary for another
    # architecture. In a git worktree <repo> is the worktree; the main checkout is tried too.
    MAIN_ROOT="$(cd "$ROOT" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    MAIN_ROOT="${MAIN_ROOT%/.git}"
    for C in "$EMU/node_modules/.bin/firebase" "$ROOT/.emulator/node_modules/.bin/firebase" \
        ${MAIN_ROOT:+"$MAIN_ROOT/.emulator/node_modules/.bin/firebase"}; do
      if [ -x "$C" ]; then CLI="$C"; break; fi
    done
    [ -n "$CLI" ] || CLI="$(command -v firebase || true)"
  fi
  if [ -z "$CLI" ]; then
    echo "The firebase CLI was not found. Install it (mkdir -p .emulator && cd .emulator &&"
    echo "npm init -y && npm install firebase-tools) or set FIREBASE_CLI."
    exit 1
  fi
  # Fail now, with the reason, when the binary can't run (for example "Bad CPU type in
  # executable": a firebase binary built for another architecture).
  if ! CLI_CHECK="$("$CLI" --version 2>&1)"; then
    echo "The firebase CLI $CLI cannot run:"
    echo "  $CLI_CHECK"
    case "$CLI_CHECK" in
      *"Bad CPU type"*|*"cannot execute binary"*|*"Exec format error"*)
        echo "It was built for another CPU architecture.";;
    esac
    echo "Install firebase-tools locally (mkdir -p .emulator && cd .emulator && npm init -y &&"
    echo "npm install firebase-tools) or set FIREBASE_CLI to a firebase command that runs here."
    exit 1
  fi
  # A configuration of its own: only the Auth emulator, with its hub and logging ports moved off
  # the CLI defaults (4400, 4500) so that it does not collide with another emulator suite.
  cat >"$AUTH_CFG/firebase.json" <<JSON
{
  "emulators": {
    "auth": {"host": "127.0.0.1", "port": $AUTH_PORT},
    "hub": {"host": "127.0.0.1", "port": $HUB_PORT},
    "logging": {"host": "127.0.0.1", "port": $LOGGING_PORT},
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
  echo "Auth emulator up on 127.0.0.1:$AUTH_PORT, hub $HUB_PORT, logging $LOGGING_PORT (pid $(cat "$AUTH_PID"), log $AUTH_LOG)"
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
