#!/usr/bin/env bash
ROOT0="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT0/.emulator}"
PID="$EMU/emulator.pid"
if [ -f "$PID" ]; then
  P="$(cat "$PID")"
  # stop the child processes (java) first, then the CLI
  pkill -TERM -P "$P" 2>/dev/null
  kill -TERM "$P" 2>/dev/null
  rm -f "$PID"
  echo "Stopped emulator (pid $P)"
else
  echo "No pid file; emulator not running"
fi
