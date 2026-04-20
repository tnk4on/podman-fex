#!/bin/bash
# Issue #23219: gawk SIGSEGV under QEMU
# https://github.com/containers/podman/issues/23219
set +e

TEST_NAME="13b-gawk"
TIMEOUT=300
CN="fex-${TEST_NAME}-$$"
IMAGE="docker.io/library/debian:bookworm-slim"
WORKSPACE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_HELPER="${WORKSPACE_DIR}/scripts/podman-cache-image.sh"

echo "=== TEST: ${TEST_NAME} ==="
echo "Issue: #23219 - gawk SIGSEGV under QEMU (OpenWrt imagebuilder)"
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
  sh -c 'apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq gawk >/dev/null 2>&1 && gawk --version | head -1' 2>&1

EXIT_CODE=$?
pkill -P $WD 2>/dev/null; kill $WD 2>/dev/null; wait $WD 2>/dev/null
[ $EXIT_CODE -eq 137 ] && EXIT_CODE=124
echo ""
echo "=== RESULT: ${TEST_NAME} - exit code: ${EXIT_CODE} ==="
exit $EXIT_CODE
