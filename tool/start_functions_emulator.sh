#!/usr/bin/env bash
# Starts a private Firebase Functions emulator (part of firebase-tools, Node) in the background, on
# 127.0.0.1:<port>, with the fixture functions of tool/functions_emulator/functions (project demo-functions,
# region us-central1).
#
# Usage: tool/start_functions_emulator.sh [port]     (default 9501; the CLI's own default is 5001)
#
# The pid file and the log are in EMULATOR_DIR. Stop it with tool/stop_functions_emulator.sh [port].
#
# Needs Node 22 and firebase-tools (15.18.0 is the version the fixture was measured with), and the fixture's
# packages: npm ci --prefix tool/functions_emulator/functions
#
# Environment:
#   EMULATOR_DIR            directory for the pid file and the log (default: <repo>/.emulator)
#   FIREBASE_CLI            the firebase command (default: the first of
#                           $EMULATOR_DIR/node_modules/.bin/firebase,
#                           <repo>/.emulator/node_modules/.bin/firebase (in a git worktree also the one
#                           of the main checkout), and `firebase` on the PATH)
#   FUNCTIONS_HUB_PORT      port of the emulator hub (default: port + 1; the CLI's own default is 4400)
#   FUNCTIONS_LOGGING_PORT  port of its logging server (default: port + 2; CLI default 4500)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT/.emulator}"
PORT="${1:-9501}"
HUB_PORT="${FUNCTIONS_HUB_PORT:-$((PORT + 1))}"
LOGGING_PORT="${FUNCTIONS_LOGGING_PORT:-$((PORT + 2))}"
for P in "$PORT" "$HUB_PORT" "$LOGGING_PORT"; do
  case "$P" in
  '' | *[!0-9]*)
    echo "Usage: $0 [port] (ports are numbers: $P)"
    exit 2
    ;;
  8080 | 8181 | 9099 | 9199 | 4400 | 4500 | 5001)
    echo "$P is a shared or default emulator port; pick another one."
    exit 2
    ;;
  esac
done
PID="$EMU/functions_emulator_$PORT.pid"
LOG="$EMU/functions_emulator_$PORT.log"
CFG="$ROOT/tool/functions_emulator/functions_emulator_$PORT.json"

if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "Functions emulator already running on port $PORT (pid $(cat "$PID"))"
  echo "export FIREBASE_FUNCTIONS_EMULATOR_HOST=127.0.0.1:$PORT"
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
  echo "npm init -y && npm install firebase-tools@15.18.0) or set FIREBASE_CLI."
  exit 1
fi
if ! CLI_CHECK="$("$CLI" --version 2>&1)"; then
  echo "The firebase CLI $CLI cannot run:"
  echo "  $CLI_CHECK"
  echo "Install firebase-tools locally or set FIREBASE_CLI to a firebase command that runs here."
  exit 1
fi

if [ ! -d "$ROOT/tool/functions_emulator/functions/node_modules" ]; then
  echo "The fixture's packages are not installed. Run:"
  echo "  npm ci --prefix tool/functions_emulator/functions"
  exit 1
fi

mkdir -p "$EMU"
# A configuration of its own: only the Functions emulator, hub and logging ports off the CLI defaults. The
# relative source is resolved next to this file.
cat >"$CFG" <<JSON
{
  "functions": {"source": "functions", "runtime": "nodejs22"},
  "emulators": {
    "functions": {"host": "127.0.0.1", "port": $PORT},
    "hub": {"host": "127.0.0.1", "port": $HUB_PORT},
    "logging": {"host": "127.0.0.1", "port": $LOGGING_PORT},
    "ui": {"enabled": false}
  }
}
JSON
# exec: the pid file holds the pid of the CLI (node) itself; the config path in its command line is what the
# stop script's guard matches.
(cd "$ROOT/tool/functions_emulator" && exec nohup "$CLI" emulators:start --only functions \
  --project demo-functions --config "$CFG" >"$LOG" 2>&1) &
echo $! >"$PID"

# Ready means the fixture answers: -f makes curl fail on any status from 400 up, so the router's 404 ("Function
# ... does not exist"), which firebase-tools sends between opening its listener and loading the triggers, does
# not count; only echo's 200 does.
ready() {
  curl -sf --max-time 5 -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"data":null}' \
    "http://127.0.0.1:$PORT/demo-functions/us-central1/echo"
}
for _ in $(seq 1 90); do
  ready && break
  kill -0 "$(cat "$PID")" 2>/dev/null || {
    echo "The Functions emulator died, see $LOG"
    tail -20 "$LOG"
    rm -f "$PID"
    exit 1
  }
  sleep 1
done
ready || {
  echo "Timed out waiting for the Functions emulator, see $LOG"
  exit 1
}
echo "Functions emulator up on 127.0.0.1:$PORT, hub $HUB_PORT, logging $LOGGING_PORT (pid $(cat "$PID"), log $LOG)"
echo "export FIREBASE_FUNCTIONS_EMULATOR_HOST=127.0.0.1:$PORT"
