#!/usr/bin/env bash
# Starts a private Firestore emulator in Standard edition on 127.0.0.1:<port> (project
# demo-test) in the background, next to the shared one of start_emulator.sh (port 8080). For
# runs that are hard on the emulator and must not disturb anybody else: the browser tests and
# the integration suite over the web transport (see "Web transport and the emulator" in
# tool/README.md).
#
# Usage: tool/start_private_emulator.sh [port]     (default port: 8090)
#
# The emulator JAR is run directly with java, like start_enterprise_emulator.sh. Each port has
# its own pid file and log. Stop it with tool/stop_private_emulator.sh [port].
#
# Environment:
#   EMULATOR_DIR            directory for the pid file and the log (default: <repo>/.emulator)
#   FIRESTORE_EMULATOR_JAR  emulator JAR (default: the newest cloud-firestore-emulator-v*.jar in
#                           ~/.cache/firebase/emulators, where the Firebase CLI downloads it)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT/.emulator}"
PKG="$ROOT/cloud_firestore/cloud_firestore_dart"
PORT="${1:-8090}"
case "$PORT" in
  ''|*[!0-9]*) echo "Usage: $0 [port]"; exit 2;;
  8080) echo "8080 is the shared emulator (start_emulator.sh); pick another port."; exit 2;;
esac
PID="$EMU/private_emulator_$PORT.pid"
LOG="$EMU/private_emulator_$PORT.log"

mkdir -p "$EMU" || exit 1

if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "Private emulator already running on port $PORT (pid $(cat "$PID"))"; exit 0
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

ARGS=(--host 127.0.0.1 --port "$PORT" --database-edition standard --project_id demo-test)
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
    echo "Private Firestore emulator up on 127.0.0.1:$PORT (pid $(cat "$PID"), log $LOG)"
    echo "export FIRESTORE_EMULATOR_HOST=127.0.0.1:$PORT"
    exit 0
  fi
  kill -0 "$(cat "$PID")" 2>/dev/null || {
    echo "Private emulator died, see $LOG"; tail -20 "$LOG"; rm -f "$PID"; exit 1; }
  sleep 1
done
echo "Timed out waiting for the private emulator, see $LOG"; exit 1
