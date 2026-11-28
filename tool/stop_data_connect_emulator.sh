#!/usr/bin/env bash
# Stops the Data Connect emulator that tool/start_data_connect_emulator.sh started on this port, and only
# that process.
#
# Usage: tool/stop_data_connect_emulator.sh [port]     (default 9499)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT/.emulator}"
PORT="${1:-9499}"
case "$PORT" in
'' | *[!0-9]*)
  echo "Usage: $0 [port]"
  exit 2
  ;;
esac
PIDFILE="$EMU/data_connect_emulator_$PORT.pid"
if [ ! -f "$PIDFILE" ]; then
  echo "No pid file for the Data Connect emulator ($PIDFILE)"
  exit 0
fi
P="$(cat "$PIDFILE")"
if ! kill -0 "$P" 2>/dev/null; then
  echo "The Data Connect emulator (pid $P) is not running; removing the stale pid file"
  rm -f "$PIDFILE"
  exit 0
fi
# Guard against a recycled pid: the process must be the emulator this script expects.
CMD="$(ps -p "$P" -o command= 2>/dev/null || true)"
case "$CMD" in
*firebase*emulators:start*data_connect_emulator_"$PORT"*) ;;
*)
  echo "Pid $P is not the Data Connect emulator of port $PORT (pid was reused?); not stopping it."
  rm -f "$PIDFILE"
  exit 1
  ;;
esac
kill -INT "$P" 2>/dev/null || true
for _ in $(seq 1 30); do
  kill -0 "$P" 2>/dev/null || break
  sleep 0.5
done
if kill -0 "$P" 2>/dev/null; then
  echo "The Data Connect emulator (pid $P) did not stop; sending SIGKILL"
  kill -KILL "$P" 2>/dev/null || true
fi
rm -f "$PIDFILE"
echo "Stopped the Data Connect emulator (pid $P)"
