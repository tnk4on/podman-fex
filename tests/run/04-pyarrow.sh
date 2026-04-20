#!/bin/bash
# Issue #26036: PyArrow SIGSEGV under QEMU
# https://github.com/containers/podman/issues/26036
set +e

TEST_NAME="04-pyarrow"
TIMEOUT=60
CN="fex-${TEST_NAME}-$$"

echo "=== TEST: ${TEST_NAME} ==="
echo "Issue: #26036 - PyArrow import SIGSEGV"
echo ""

IMAGE="docker.io/library/python:3.11-slim"
WORKSPACE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_HELPER="${WORKSPACE_DIR}/scripts/podman-cache-image.sh"

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
  bash -c 'pip install pyarrow==20.0.0 && python -c "import pyarrow; print(\"pyarrow version:\", pyarrow.__version__)"' 2>&1

EXIT_CODE=$?
pkill -P $WD 2>/dev/null; kill $WD 2>/dev/null; wait $WD 2>/dev/null
[ $EXIT_CODE -eq 137 ] && EXIT_CODE=124
echo ""
echo "=== RESULT: ${TEST_NAME} - exit code: ${EXIT_CODE} ==="
exit $EXIT_CODE
