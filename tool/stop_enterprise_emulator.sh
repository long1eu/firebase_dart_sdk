#!/usr/bin/env bash
# Stops the Enterprise edition Firestore emulator started by start_enterprise_emulator.sh.
# Only the process recorded in the pid file is signalled, and only if it still is a Firestore
# emulator: the standard emulator (start_emulator.sh) and any other process are left alone.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT/.emulator}"
PID="$EMU/enterprise_emulator.pid"

if [ ! -f "$PID" ]; then
  echo "No pid file; enterprise emulator not running"; exit 0
fi

P="$(cat "$PID")"
case "$P" in
  ''|*[!0-9]*) echo "Invalid pid file $PID; removing it"; rm -f "$PID"; exit 1;;
esac

if ! kill -0 "$P" 2>/dev/null; then
  echo "Enterprise emulator (pid $P) is not running; removing the stale pid file"
  rm -f "$PID"; exit 0
fi

# Guard against a recycled pid: the process must be the emulator in enterprise edition.
CMD="$(ps -p "$P" -o command= 2>/dev/null)"
case "$CMD" in
  *cloud-firestore-emulator*--database-edition\ enterprise*) ;;
  *)
    echo "Pid $P is not the enterprise emulator (pid was reused?); not stopping it."
    echo "Removing the stale pid file."
    rm -f "$PID"; exit 1;;
esac

kill -TERM "$P" 2>/dev/null
for _ in $(seq 1 20); do
  kill -0 "$P" 2>/dev/null || break
  sleep 0.5
done
if kill -0 "$P" 2>/dev/null; then
  echo "Enterprise emulator (pid $P) did not stop after SIGTERM; sending SIGKILL"
  kill -KILL "$P" 2>/dev/null
fi
rm -f "$PID"
echo "Stopped enterprise emulator (pid $P)"
