#!/bin/bash
# Issue #27320: jemalloc SIGSEGV under QEMU
# https://github.com/containers/podman/issues/27320
set +e

TEST_NAME="05-jemalloc"
TIMEOUT=300
CN="fex-${TEST_NAME}-$$"
IMAGE="docker.io/library/ubuntu:latest"
WORKSPACE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_HELPER="${WORKSPACE_DIR}/scripts/podman-cache-image.sh"

echo "=== TEST: ${TEST_NAME} ==="
echo "Issue: #27320 - jemalloc LD_PRELOAD SIGSEGV"
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
  bash -c 'apt-get update -qq && apt-get install -y -qq libjemalloc2 > /dev/null 2>&1 && echo "jemalloc installed" && LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 /usr/bin/echo "jemalloc loaded successfully"' 2>&1

EXIT_CODE=$?
pkill -P $WD 2>/dev/null; kill $WD 2>/dev/null; wait $WD 2>/dev/null
[ $EXIT_CODE -eq 137 ] && EXIT_CODE=124
echo ""
echo "=== RESULT: ${TEST_NAME} - exit code: ${EXIT_CODE} ==="
exit $EXIT_CODE
