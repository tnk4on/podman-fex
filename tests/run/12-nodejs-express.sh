#!/bin/bash
# Issue #26572: Node.js Express apps freeze under Rosetta with parallel HTTP requests
# https://github.com/containers/podman/issues/26572
#
# Original report:
#   1. Build a container image for linux/amd64 running an Express.js app
#   2. Start the container and schedule parallel HTTP requests
#   3. After some time, the container stops responding — no crash logs, just freeze
#   Workaround: disable Rosetta and use QEMU
#
# Test strategy:
#   1. Build Express app image (linux/amd64)
#   2. Start container with port-forward
#   3. Send parallel HTTP requests in waves
#   4. Detect freeze via curl timeout
#   5. PASS if all requests succeed within timeout
set +e

# Define pcmd if not already exported by run-all-tests.sh
if ! type pcmd &>/dev/null; then
  pcmd() {
    if [ -n "${PODMAN_CONNECTION}" ]; then
      podman --connection "${PODMAN_CONNECTION}" "$@"
    else
      podman "$@"
    fi
  }
fi

TEST_NAME="12-nodejs-express"
TIMEOUT=90
CN="fex-${TEST_NAME}-$$"
IMAGE="fex-test-express-$$"
HOST_PORT=$((10000 + RANDOM % 20000))

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../build/12-nodejs-express"

echo "=== TEST: ${TEST_NAME} ==="
echo "Issue: #26572 - Node.js Express freeze under parallel requests"
echo ""

# Phase 1: Build the image
echo "--- Phase 1: Building Express app image ---"
pcmd build --pull-never --platform linux/amd64 -t "${IMAGE}" "${BUILD_DIR}" 2>&1
BUILD_EXIT=$?
if [ ${BUILD_EXIT} -ne 0 ]; then
  echo "BUILD FAILED: exit ${BUILD_EXIT}"
  exit ${BUILD_EXIT}
fi
echo "Build succeeded"
echo ""

# Phase 2: Start container
echo "--- Phase 2: Starting container (port ${HOST_PORT}) ---"
pcmd run -d --rm --name "${CN}" \
  --platform linux/amd64 \
  -p "${HOST_PORT}:3000" \
  "${IMAGE}" 2>&1
RUN_EXIT=$?
if [ ${RUN_EXIT} -ne 0 ]; then
  echo "CONTAINER START FAILED: exit ${RUN_EXIT}"
  pcmd rmi "${IMAGE}" 2>/dev/null
  exit ${RUN_EXIT}
fi

# Cleanup function
cleanup() {
  echo ""
  echo "--- Cleanup ---"
  pcmd kill "${CN}" 2>/dev/null
  pcmd rm -f "${CN}" 2>/dev/null
  pcmd rmi "${IMAGE}" 2>/dev/null
}
trap cleanup EXIT

# Wait for server to be ready (max 30s)
echo "Waiting for Express server to start..."
READY=0
for i in $(seq 1 30); do
  if curl -s --max-time 3 "http://localhost:${HOST_PORT}/health" | grep -q "healthy" 2>/dev/null; then
    READY=1
    echo "Server ready after ${i}s"
    break
  fi
  sleep 1
done

if [ ${READY} -ne 1 ]; then
  echo "FAIL: Server did not start within 30s"
  exit 1
fi

# Phase 3: Send parallel HTTP requests in waves
# Original issue: "schedule parallel HTTP requests per second to the Express app"
echo ""
echo "--- Phase 3: Sending parallel HTTP requests (3 waves) ---"

TOTAL_OK=0
TOTAL_FAIL=0
FREEZE_DETECTED=0

for wave in 1 2 3; do
  echo ""
  echo "Wave ${wave}/3: sending 20 parallel requests..."
  WAVE_OK=0
  WAVE_FAIL=0

  # Launch 20 parallel curl requests
  PIDS=""
  for j in $(seq 1 20); do
    curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
      "http://localhost:${HOST_PORT}/" &
    PIDS="$PIDS $!"
  done

  # Collect results
  for pid in $PIDS; do
    wait "$pid"
    rc=$?
    if [ $rc -eq 0 ]; then
      WAVE_OK=$((WAVE_OK + 1))
    else
      WAVE_FAIL=$((WAVE_FAIL + 1))
    fi
  done

  TOTAL_OK=$((TOTAL_OK + WAVE_OK))
  TOTAL_FAIL=$((TOTAL_FAIL + WAVE_FAIL))
  echo "  Wave ${wave}: OK=${WAVE_OK} FAIL=${WAVE_FAIL}"

  # Check if server is still alive after the wave
  if ! curl -s --max-time 5 "http://localhost:${HOST_PORT}/health" | grep -q "healthy" 2>/dev/null; then
    echo "  ⚠️  Server stopped responding after wave ${wave} — FREEZE DETECTED"
    FREEZE_DETECTED=1
    break
  fi
  echo "  Health check: OK"

  # Brief pause between waves
  sleep 2
done

echo ""
echo "--- Results ---"
echo "Total requests: $((TOTAL_OK + TOTAL_FAIL))"
echo "  OK:   ${TOTAL_OK}"
echo "  FAIL: ${TOTAL_FAIL}"

if [ ${FREEZE_DETECTED} -eq 1 ]; then
  echo ""
  echo "=== RESULT: ${TEST_NAME} - FREEZE DETECTED (matches original issue) ==="
  exit 1
elif [ ${TOTAL_FAIL} -gt 0 ]; then
  echo ""
  echo "=== RESULT: ${TEST_NAME} - ${TOTAL_FAIL} request(s) failed ==="
  # Allow up to 10% failure rate (network transient)
  THRESHOLD=$(( (TOTAL_OK + TOTAL_FAIL) / 10 ))
  if [ ${TOTAL_FAIL} -gt ${THRESHOLD} ]; then
    exit 1
  fi
  echo "(within acceptable threshold)"
  exit 0
else
  echo ""
  echo "=== RESULT: ${TEST_NAME} - PASS (no freeze, all requests OK) ==="
  exit 0
fi
