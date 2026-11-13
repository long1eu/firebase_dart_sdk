#!/usr/bin/env bash
# Stops the emulators that tool/start_auth_emulators.sh started on these ports, and only those
# processes.
#
# Usage: tool/stop_auth_emulators.sh [auth port] [firestore port]     (defaults: 9197 8197)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${EMULATOR_DIR:-$ROOT/.emulator}"
AUTH_PORT="${1:-9197}"
FS_PORT="${2:-8197}"
for P in "$AUTH_PORT" "$FS_PORT"; do
  case "$P" in
    ''|*[!0-9]*) echo "Usage: $0 [auth port] [firestore port]"; exit 2;;
  esac
done

# stop <pid file> <what> <pattern the command line must match> <signal>
stop() {
  local PIDFILE="$1" WHAT="$2" PATTERN="$3" SIGNAL="$4"
  if [ ! -f "$PIDFILE" ]; then
    echo "No pid file for the $WHAT ($PIDFILE)"; return 0
  fi
  local P; P="$(cat "$PIDFILE")"
  if ! kill -0 "$P" 2>/dev/null; then
    echo "The $WHAT (pid $P) is not running; removing the stale pid file"
    rm -f "$PIDFILE"; return 0
  fi
  # Guard against a recycled pid: the process must be the emulator this script expects.
  local CMD; CMD="$(ps -p "$P" -o command= 2>/dev/null)"
  case "$CMD" in
    $PATTERN) ;;
    *)
      echo "Pid $P is not the $WHAT (pid was reused?); not stopping it. Removing the stale pid file."
      rm -f "$PIDFILE"; return 1;;
  esac
  kill "-$SIGNAL" "$P" 2>/dev/null
  for _ in $(seq 1 30); do
    kill -0 "$P" 2>/dev/null || break
    sleep 0.5
  done
  if kill -0 "$P" 2>/dev/null; then
    echo "The $WHAT (pid $P) did not stop; sending SIGKILL"
    kill -KILL "$P" 2>/dev/null
  fi
  rm -f "$PIDFILE"
  echo "Stopped the $WHAT (pid $P)"
}

# The CLI shuts its emulator down on SIGINT.
stop "$EMU/auth_emulator_$AUTH_PORT.pid" "Auth emulator of port $AUTH_PORT" \
  "*firebase*emulators:start*auth_emulator_$AUTH_PORT*" INT
stop "$EMU/auth_firestore_emulator_$FS_PORT.pid" "Firestore emulator (auth rules) of port $FS_PORT" \
  "*cloud-firestore-emulator*--port $FS_PORT *" TERM
