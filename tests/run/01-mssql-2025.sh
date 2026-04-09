#!/bin/bash
# Issue #28184: MSSQL 2025 AVX instruction crash
# https://github.com/containers/podman/issues/28184
set +e

TEST_NAME="01-mssql-2025"
TIMEOUT=90
CN="fex-${TEST_NAME}-$$"

echo "=== TEST: ${TEST_NAME} ==="
echo "Issue: #28184 - MSSQL 2025 AVX instruction crash"
echo ""

( sleep $TIMEOUT; pcmd kill "$CN" 2>/dev/null ) &
WD=$!

pcmd run --rm --name "$CN" \
  -e 'ACCEPT_EULA=Y' -e 'SA_PASSWORD=Str0ng!Passw0rd' \
  --arch amd64 mcr.microsoft.com/mssql/server:2025-latest 2>&1

EXIT_CODE=$?
pkill -P $WD 2>/dev/null; kill $WD 2>/dev/null; wait $WD 2>/dev/null
[ $EXIT_CODE -eq 137 ] && EXIT_CODE=124
echo ""
echo "=== RESULT: ${TEST_NAME} - exit code: ${EXIT_CODE} ==="
exit $EXIT_CODE
