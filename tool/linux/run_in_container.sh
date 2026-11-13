#!/usr/bin/env bash
# Runs the tests in a Linux container (Docker), from a machine that is not Linux: the unit tests of the packages
# (tool/test_all.sh) and the standard integration suite (tool/test_integration.sh standard) against a Firestore
# emulator started inside the container from the emulator JAR. Nothing in the container talks to an emulator of the
# host.
#
# Usage: tool/linux/run_in_container.sh [unit|integration|all] [platform]
#
#   unit         tool/test_all.sh, with FIRESTORE_TEST_NET_ADMIN=1 (the container may change its network interfaces,
#                for test/unit/firebase/firestore/remote/connectivity_interface_change_test.dart)
#   integration  tool/test_integration.sh standard, against an emulator on 127.0.0.1:8090 in the container
#   all          (default) both
#   platform     linux/arm64 or linux/amd64 (default: the one of the Docker server); the other one runs emulated
#                (much slower)
#
# The files of the working tree that git knows about (tracked, and untracked but not ignored) are copied into the
# container; nothing is mounted. The container is named fsdart-linux-test-<arch>-<pid> and is removed on exit; the
# image (fsdart-linux-test:<arch>) is kept.
#
# Environment:
#   FIRESTORE_EMULATOR_JAR  emulator JAR (default: the newest cloud-firestore-emulator-v*.jar in
#                           ~/.cache/firebase/emulators); only read, copied into the container
#   DART_IMAGE              base image (default dart:stable)
#   TEST_LOG_DIR            where the logs of the container are copied (default: a new temp dir)
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:-all}"
case "$MODE" in
  unit|integration|all) ;;
  *) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 2;;
esac
PLATFORM="${2:-linux/$(docker version --format '{{.Server.Arch}}')}"
ARCH="${PLATFORM#linux/}"
IMAGE="fsdart-linux-test:$ARCH"
NAME="fsdart-linux-test-$ARCH-$$"
LOG="${TEST_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOG" || exit 2

JAR="${FIRESTORE_EMULATOR_JAR:-$(ls "$HOME"/.cache/firebase/emulators/cloud-firestore-emulator-v*.jar 2>/dev/null \
  | sort -V | tail -1)}"
if [ "$MODE" != unit ] && { [ -z "$JAR" ] || [ ! -f "$JAR" ]; }; then
  echo "Firestore emulator JAR not found; set FIRESTORE_EMULATOR_JAR."; exit 2
fi

docker build --platform "$PLATFORM" --build-arg "DART_IMAGE=${DART_IMAGE:-dart:stable}" -t "$IMAGE" \
  "$ROOT/tool/linux" >"$LOG/docker_build.log" 2>&1 || { tail -20 "$LOG/docker_build.log"; exit 1; }

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1; }
trap cleanup EXIT
docker run -d --name "$NAME" --platform "$PLATFORM" --cap-add NET_ADMIN "$IMAGE" sleep infinity >/dev/null || exit 1

# COPYFILE_DISABLE and --no-xattrs: no AppleDouble (._*) files from macOS, which `dart test` would try to load.
(cd "$ROOT" && git ls-files -co --exclude-standard -z \
  | COPYFILE_DISABLE=1 tar --no-xattrs --null -cf - -T -) \
  | docker exec -i "$NAME" sh -c 'mkdir -p /src && tar -xf - -C /src' 2>/dev/null || exit 1
if [ "$MODE" != unit ]; then
  docker exec "$NAME" mkdir -p /root/.cache/firebase/emulators
  docker cp "$JAR" "$NAME:/root/.cache/firebase/emulators/$(basename "$JAR")" >/dev/null || exit 1
fi
docker exec "$NAME" sh -c 'uname -m; dart --version; java -version 2>&1 | head -1' | tee "$LOG/versions.txt"

failed=0
if [ "$MODE" != integration ]; then
  docker exec -e TEST_LOG_DIR=/logs/unit -e FIRESTORE_TEST_NET_ADMIN=1 "$NAME" /src/tool/test_all.sh || failed=1
fi
if [ "$MODE" != unit ]; then
  docker exec -e EMULATOR_DIR=/logs/emulator "$NAME" /src/tool/start_private_emulator.sh 8090 || exit 1
  docker exec "$NAME" sh -c 'cd /src/cloud_firestore/cloud_firestore_dart && dart pub get >/dev/null' || exit 1
  docker exec -e FIRESTORE_EMULATOR_HOST=127.0.0.1:8090 -e TEST_LOG_DIR=/logs/integration "$NAME" \
    /src/tool/test_integration.sh standard || failed=1
fi
docker cp "$NAME:/logs/." "$LOG" >/dev/null 2>&1
echo "Logs in $LOG"
exit $failed
