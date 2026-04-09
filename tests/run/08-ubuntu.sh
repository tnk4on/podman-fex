#!/bin/bash
# Issue #27799: Ubuntu 25.10 terminal attach hang
# https://github.com/containers/podman/issues/27799
set +e

TEST_NAME="08-ubuntu"
TIMEOUT=30
CN="fex-${TEST_NAME}-$$"
IMAGE="docker.io/library/ubuntu:25.10"
WORKSPACE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_HELPER="${WORKSPACE_DIR}/scripts/podman-cache-image.sh"

echo "=== TEST: ${TEST_NAME} ==="
echo "Issue: #27799 - Ubuntu 25.10 bash hangs"
echo ""

if [ -x "${CACHE_HELPER}" ]; then
  if [ -n "${PODMAN_CONNECTION:-}" ]; then
    "${CACHE_HELPER}" --quiet --connection "${PODMAN_CONNECTION}" --platform linux/amd64 "${IMAGE}" || exit 1
  else
    "${CACHE_HELPER}" --quiet --platform linux/amd64 "${IMAGE}" || exit 1
  fi
fi

( sleep $TIMEOUT; pcmd kill "$CN" 2>/dev/null ) &
WD=$!

pcmd run --rm --name "$CN" \
  --arch amd64 "${IMAGE}" \
  bash -c 'echo "Ubuntu running successfully" && uname -a && cat /etc/os-release' 2>&1

EXIT_CODE=$?
pkill -P $WD 2>/dev/null; kill $WD 2>/dev/null; wait $WD 2>/dev/null
[ $EXIT_CODE -eq 137 ] && EXIT_CODE=124
echo ""
echo "=== RESULT: ${TEST_NAME} - exit code: ${EXIT_CODE} ==="
exit $EXIT_CODE
