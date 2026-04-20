#!/bin/bash
# Issue #26656: su -l not login shell under Rosetta
# https://github.com/containers/podman/issues/26656
set +e

TEST_NAME="16-su-login-shell"
TIMEOUT=60
CN="fex-${TEST_NAME}-$$"

echo "=== TEST: ${TEST_NAME} ==="
echo "Issue: #26656 - su -l does not start login shell (breaks DB2, etc.)"
echo ""

( sleep $TIMEOUT; pcmd kill "$CN" 2>/dev/null ) &
WD=$!

pcmd run --rm --name "$CN" \
  --platform linux/amd64 registry.access.redhat.com/ubi8:latest \
  sh -c 'useradd appuser && su -l appuser -c "shopt -q login_shell && echo Login_shell || echo Not_login_shell"' 2>&1

EXIT_CODE=$?
pkill -P $WD 2>/dev/null; kill $WD 2>/dev/null; wait $WD 2>/dev/null
[ $EXIT_CODE -eq 137 ] && EXIT_CODE=124
echo ""
echo "=== RESULT: ${TEST_NAME} - exit code: ${EXIT_CODE} ==="
exit $EXIT_CODE
