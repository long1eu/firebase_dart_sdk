#!/usr/bin/env bash
# Stops the private Firestore emulator that tool/start_private_emulator.sh started on a port,
# and only that process.
#
# Usage: tool/stop_private_emulator.sh [port]     (default port: 8090)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT/.emulator}"
PORT="${1:-8090}"
case "$PORT" in
  ''|*[!0-9]*) echo "Usage: $0 [port]"; exit 2;;
esac
PID="$EMU/private_emulator_$PORT.pid"

if [ ! -f "$PID" ]; then
  echo "No private emulator pid file for port $PORT ($PID)"; exit 0
fi
P="$(cat "$PID")"
if ! kill -0 "$P" 2>/dev/null; then
  echo "Private emulator (pid $P) is not running; removing the stale pid file"
  rm -f "$PID"; exit 0
fi

# Guard against a recycled pid: the process must be the emulator on this port.
CMD="$(ps -p "$P" -o command= 2>/dev/null)"
case "$CMD" in
  *cloud-firestore-emulator*--port\ "$PORT"\ *) ;;
  *)
    echo "Pid $P is not the private emulator of port $PORT (pid was reused?); not stopping it."
    echo "Removing the stale pid file."
    rm -f "$PID"; exit 1;;
esac

kill -TERM "$P" 2>/dev/null
for _ in $(seq 1 20); do
  kill -0 "$P" 2>/dev/null || break
  sleep 0.5
done
if kill -0 "$P" 2>/dev/null; then
  echo "Private emulator (pid $P) did not stop after SIGTERM; sending SIGKILL"
  kill -KILL "$P" 2>/dev/null
fi
rm -f "$PID"
echo "Stopped private emulator on port $PORT (pid $P)"
