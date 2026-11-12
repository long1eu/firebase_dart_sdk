#!/usr/bin/env bash
# Starts a second Firestore emulator in Enterprise edition on 127.0.0.1:8181 (project
# demo-test) in the background. It is independent of the standard emulator started by
# start_emulator.sh (port 8080) and has its own pid file and log.
#
# The emulator JAR is run directly with java (the Firebase CLI is not involved), because the
# CLI takes the edition from firebase.json and can only run one Firestore emulator.
#
# Environment:
#   EMULATOR_DIR              directory for the pid file and the log (default: <repo>/.emulator)
#   FIRESTORE_EMULATOR_JAR    emulator JAR (default: the newest cloud-firestore-emulator-v*.jar in
#                             ~/.cache/firebase/emulators, where the Firebase CLI downloads it)
#   ENTERPRISE_EMULATOR_PORT  port to listen on (default: 8181)
#
# Tests find it through FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT/.emulator}"
PKG="$ROOT/cloud_firestore/cloud_firestore_dart"
PORT="${ENTERPRISE_EMULATOR_PORT:-8181}"
PID="$EMU/enterprise_emulator.pid"
LOG="$EMU/enterprise_emulator.log"

mkdir -p "$EMU" || exit 1

if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "Enterprise emulator already running (pid $(cat "$PID"))"; exit 0
fi

if curl -s -o /dev/null "http://127.0.0.1:$PORT"; then
  echo "Port $PORT is already in use by a process this script did not start; not starting."
  exit 1
fi

JAR="${FIRESTORE_EMULATOR_JAR:-}"
if [ -z "$JAR" ]; then
  # Newest version (version sort of the file names).
  JAR="$(ls "$HOME"/.cache/firebase/emulators/cloud-firestore-emulator-v*.jar 2>/dev/null \
    | sort -V | tail -1)"
fi
if [ -z "$JAR" ] || [ ! -f "$JAR" ]; then
  echo "Firestore emulator JAR not found. Start the standard emulator once (the Firebase CLI"
  echo "downloads the JAR to ~/.cache/firebase/emulators) or set FIRESTORE_EMULATOR_JAR."
  exit 1
fi
command -v java >/dev/null 2>&1 || { echo "java not found on PATH"; exit 1; }

ARGS=(--host 127.0.0.1 --port "$PORT" --database-edition enterprise --project_id demo-test)
if [ -f "$PKG/firestore.rules" ]; then
  ARGS+=(--rules "$PKG/firestore.rules")
fi

echo "Using $JAR"
# The pid file holds the pid of the java process itself, so that the stop script can stop
# exactly this process.
nohup java -Duser.language=en -jar "$JAR" "${ARGS[@]}" >"$LOG" 2>&1 &
echo $! >"$PID"

for _ in $(seq 1 120); do
  if curl -s -o /dev/null "http://127.0.0.1:$PORT"; then
    echo "Firestore Enterprise emulator up on 127.0.0.1:$PORT (pid $(cat "$PID"), log $LOG)"
    echo "export FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:$PORT"
    exit 0
  fi
  kill -0 "$(cat "$PID")" 2>/dev/null || {
    echo "Enterprise emulator died, see $LOG"; tail -20 "$LOG"; rm -f "$PID"; exit 1; }
  sleep 1
done
echo "Timed out waiting for the enterprise emulator, see $LOG"; exit 1
