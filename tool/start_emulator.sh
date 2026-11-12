#!/usr/bin/env bash
# Starts the Firestore emulator on 127.0.0.1:8080 (project demo-test) in the background.
ROOT0="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT0/.emulator}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/cloud_firestore/cloud_firestore_vm"
PID="$EMU/emulator.pid"
LOG="$EMU/emulator.log"

if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "Emulator already running (pid $(cat "$PID"))"; exit 0
fi

# Prefer the package's config once it exists, else the temporary one.
if [ -f "$PKG/firebase.json" ] && [ -f "$PKG/firestore.rules" ]; then
  CFG_DIR="$PKG"
else
  CFG_DIR="$EMU"
fi
echo "Using config in $CFG_DIR"

cd "$CFG_DIR" || exit 1
nohup "$EMU/node_modules/.bin/firebase" emulators:start --only firestore \
  --project demo-test --config "$CFG_DIR/firebase.json" >"$LOG" 2>&1 &
echo $! >"$PID"

for _ in $(seq 1 120); do
  if curl -s -o /dev/null http://127.0.0.1:8080; then
    echo "Firestore emulator up on 127.0.0.1:8080 (pid $(cat "$PID"), log $LOG)"; exit 0
  fi
  kill -0 "$(cat "$PID")" 2>/dev/null || { echo "Emulator died, see $LOG"; tail -20 "$LOG"; exit 1; }
  sleep 1
done
echo "Timed out waiting for emulator, see $LOG"; exit 1
