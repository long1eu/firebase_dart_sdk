#!/usr/bin/env bash
# Starts a private Firebase Storage emulator (part of firebase-tools, Node) in the background, on
# 127.0.0.1:<port>, with two buckets of project demo-test:
#
#   * demo-test.appspot.com       open rules (tool/storage_emulator/open.rules);
#   * demo-test-auth.appspot.com  rules that require a signed-in user (tool/storage_emulator/auth.rules),
#                                 for tests of the 403 path.
#
# Usage: tool/start_storage_emulator.sh [port]     (default 9299; the CLI's own default is 9199)
#
# The pid file and the log are in EMULATOR_DIR. Stop it with tool/stop_storage_emulator.sh [port].
#
# Environment:
#   EMULATOR_DIR           directory for the pid file, log and generated firebase.json
#                          (default: <repo>/.emulator)
#   FIREBASE_CLI           the firebase command (default: the first of
#                          $EMULATOR_DIR/node_modules/.bin/firebase,
#                          <repo>/.emulator/node_modules/.bin/firebase (in a git worktree also the one
#                          of the main checkout), and `firebase` on the PATH)
#   STORAGE_HUB_PORT       port of the emulator hub (default: port + 1; the CLI's own default is 4400)
#   STORAGE_LOGGING_PORT   port of its logging server (default: port + 2; CLI default 4500)
#
# The storage rules runtime (cloud-storage-rules-runtime-v*.jar in ~/.cache/firebase/emulators) must
# already be downloaded; the script refuses to start otherwise, so that nothing is fetched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT/.emulator}"
PORT="${1:-9299}"
HUB_PORT="${STORAGE_HUB_PORT:-$((PORT + 1))}"
LOGGING_PORT="${STORAGE_LOGGING_PORT:-$((PORT + 2))}"
for P in "$PORT" "$HUB_PORT" "$LOGGING_PORT"; do
  case "$P" in
  '' | *[!0-9]*)
    echo "Usage: $0 [port] (ports are numbers: $P)"
    exit 2
    ;;
  8080 | 8181 | 9099 | 9199 | 4400 | 4500)
    echo "$P is a shared or default emulator port; pick another one."
    exit 2
    ;;
  esac
done
PID="$EMU/storage_emulator_$PORT.pid"
LOG="$EMU/storage_emulator_$PORT.log"
CFG="$EMU/storage_emulator_$PORT"

if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "Storage emulator already running on port $PORT (pid $(cat "$PID"))"
  echo "export FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:$PORT"
  exit 0
fi
for P in "$PORT" "$HUB_PORT" "$LOGGING_PORT"; do
  if curl -s -o /dev/null "http://127.0.0.1:$P"; then
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

if ! ls "$HOME"/.cache/firebase/emulators/cloud-storage-rules-runtime-v*.jar >/dev/null 2>&1; then
  echo "The storage rules runtime is not in ~/.cache/firebase/emulators; the CLI would download it."
  echo "Fetch it once with: $CLI setup:emulators:storage"
  exit 1
fi
command -v java >/dev/null 2>&1 || {
  echo "java not found on PATH"
  exit 1
}

mkdir -p "$EMU" "$CFG"
# A configuration of its own: only the Storage emulator, hub and logging ports off the CLI defaults.
cat >"$CFG/firebase.json" <<JSON
{
  "storage": [
    {"target": "open", "rules": "$ROOT/tool/storage_emulator/open.rules"},
    {"target": "auth", "rules": "$ROOT/tool/storage_emulator/auth.rules"}
  ],
  "emulators": {
    "storage": {"host": "127.0.0.1", "port": $PORT},
    "hub": {"host": "127.0.0.1", "port": $HUB_PORT},
    "logging": {"host": "127.0.0.1", "port": $LOGGING_PORT},
    "ui": {"enabled": false}
  }
}
JSON
cat >"$CFG/.firebaserc" <<'JSON'
{
  "projects": {"default": "demo-test"},
  "targets": {
    "demo-test": {
      "storage": {
        "open": ["demo-test.appspot.com"],
        "auth": ["demo-test-auth.appspot.com"]
      }
    }
  }
}
JSON
# exec: the pid file holds the pid of the CLI (node) itself.
(cd "$CFG" && exec nohup "$CLI" emulators:start --only storage --project demo-test \
  --config "$CFG/firebase.json" >"$LOG" 2>&1) &
echo $! >"$PID"
for _ in $(seq 1 90); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT" && break
  kill -0 "$(cat "$PID")" 2>/dev/null || {
    echo "The Storage emulator died, see $LOG"
    tail -20 "$LOG"
    rm -f "$PID"
    exit 1
  }
  sleep 1
done
curl -s -o /dev/null "http://127.0.0.1:$PORT" || {
  echo "Timed out waiting for the Storage emulator, see $LOG"
  exit 1
}
echo "Storage emulator up on 127.0.0.1:$PORT, hub $HUB_PORT, logging $LOGGING_PORT (pid $(cat "$PID"), log $LOG)"
echo "export FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:$PORT"
