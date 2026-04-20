#!/bin/bash
# Discussion #27601: redis-cluster SIGSEGV under QEMU
# https://github.com/containers/podman/discussions/27601
set +e

TEST_NAME="14-redis-cluster"
TIMEOUT=60
CN="fex-${TEST_NAME}-$$"
IMAGE="docker.io/duyquyen/redis-cluster"
WORKSPACE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_HELPER="${WORKSPACE_DIR}/scripts/podman-cache-image.sh"

echo "=== TEST: ${TEST_NAME} ==="
echo "Issue: D#27601 - redis-cluster SIGSEGV under QEMU"
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
  --platform linux/amd64 "${IMAGE}" \
  redis-server --version 2>&1

EXIT_CODE=$?
pkill -P $WD 2>/dev/null; kill $WD 2>/dev/null; wait $WD 2>/dev/null
[ $EXIT_CODE -eq 137 ] && EXIT_CODE=124
echo ""
echo "=== RESULT: ${TEST_NAME} - exit code: ${EXIT_CODE} ==="
exit $EXIT_CODE
