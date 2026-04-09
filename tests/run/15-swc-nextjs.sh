#!/bin/bash
# Issue #23269: SWC/Next.js SIGILL — Rust native binary crash
# https://github.com/containers/podman/issues/23269
set +e

TEST_NAME="15-swc-nextjs"
TIMEOUT=120
CN="fex-${TEST_NAME}-$$"
IMAGE="docker.io/library/node:lts-slim"
WORKSPACE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_HELPER="${WORKSPACE_DIR}/scripts/podman-cache-image.sh"

echo "=== TEST: ${TEST_NAME} ==="
echo "Issue: #23269 - SWC/Next.js SIGILL (Rust native binary)"
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
  bash -c 'cd /tmp && npm init -y >/dev/null 2>&1 && npm install @swc/core >/dev/null 2>&1 && node -e "const s = require(\"@swc/core\"); console.log(s.transformSync(\"const x: number = 1\", {jsc:{parser:{syntax:\"typescript\"}}}).code)"' 2>&1

EXIT_CODE=$?
pkill -P $WD 2>/dev/null; kill $WD 2>/dev/null; wait $WD 2>/dev/null
[ $EXIT_CODE -eq 137 ] && EXIT_CODE=124
echo ""
echo "=== RESULT: ${TEST_NAME} - exit code: ${EXIT_CODE} ==="
exit $EXIT_CODE
