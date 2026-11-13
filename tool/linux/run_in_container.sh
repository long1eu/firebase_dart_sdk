#!/usr/bin/env bash
# Runs the tests in a Linux container (Docker), from a machine that is not Linux: the unit tests of the packages
# (tool/test_all.sh) and the integration suites against Firestore emulators started inside the container from the
# emulator JAR. Nothing in the container talks to an emulator of the host.
#
# Usage: tool/linux/run_in_container.sh [suites] [platform]
#
#   suites       a comma-separated list of (default: unit,integration):
#     unit         tool/test_all.sh, with FIRESTORE_TEST_NET_ADMIN=1 (the container may change its network
#                  interfaces, for test/unit/firebase/firestore/remote/connectivity_interface_change_test.dart)
#     integration  tool/test_integration.sh standard, against an emulator on 127.0.0.1:8090 in the container
#     web          the same suite over the web transport, then with long polling (a fresh emulator for each)
#     enterprise   tool/test_integration.sh enterprise (the standard suite on the Enterprise edition emulator on
#                  8181, then test/integration_enterprise, which also uses the standard one on 8090)
#   all          unit,integration,web,enterprise
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
MODE="${1:-unit,integration}"
[ "$MODE" = all ] && MODE="unit,integration,web,enterprise"
for suite in ${MODE//,/ }; do
  case "$suite" in
    unit|integration|web|enterprise) ;;
    *) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 2;;
  esac
done
has() { case ",$MODE," in *",$1,"*) return 0;; esac; return 1; }
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
if has unit; then
  docker exec -e TEST_LOG_DIR=/logs/unit -e FIRESTORE_TEST_NET_ADMIN=1 "$NAME" /src/tool/test_all.sh || failed=1
fi
# A fresh standard emulator on 8090 (the web transport leaves threads behind in the emulator, see tool/README.md).
fresh_emulator() {
  docker exec -e EMULATOR_DIR=/logs/emulator "$NAME" sh -c \
    '/src/tool/stop_private_emulator.sh 8090 >/dev/null 2>&1; /src/tool/start_private_emulator.sh 8090' || exit 1
}
if [ "$MODE" != unit ]; then
  docker exec "$NAME" sh -c 'cd /src/cloud_firestore/cloud_firestore_dart && dart pub get >/dev/null' || exit 1
fi
if has integration; then
  fresh_emulator
  docker exec -e FIRESTORE_EMULATOR_HOST=127.0.0.1:8090 -e TEST_LOG_DIR=/logs/integration "$NAME" \
    /src/tool/test_integration.sh standard || failed=1
fi
if has web; then
  for transport in webchannel webchannel-longpolling; do
    fresh_emulator
    docker exec -e FIRESTORE_EMULATOR_HOST=127.0.0.1:8090 -e TEST_LOG_DIR=/logs/web "$NAME" \
      /src/tool/test_integration.sh standard --transport=$transport || failed=1
  done
fi
if has enterprise; then
  fresh_emulator
  docker exec -e EMULATOR_DIR=/logs/emulator "$NAME" /src/tool/start_enterprise_emulator.sh || exit 1
  docker exec -e FIRESTORE_EMULATOR_HOST=127.0.0.1:8090 -e FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 \
    -e TEST_LOG_DIR=/logs/enterprise "$NAME" /src/tool/test_integration.sh enterprise || failed=1
fi
docker cp "$NAME:/logs/." "$LOG" >/dev/null 2>&1
echo "Logs in $LOG"
exit $failed
