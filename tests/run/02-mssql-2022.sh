#!/bin/bash
# Issue #27078: MSSQL 2022 segfault on Apple Silicon
# https://github.com/containers/podman/issues/27078
set +e

TEST_NAME="02-mssql-2022"
TIMEOUT=90
CN="fex-${TEST_NAME}-$$"

echo "=== TEST: ${TEST_NAME} ==="
echo "Issue: #27078 - MSSQL 2022 segfault on Apple Silicon"
echo ""

( sleep $TIMEOUT; pcmd kill "$CN" 2>/dev/null ) &
WD=$!

pcmd run --rm --name "$CN" \
  --memory=4096M -e "ACCEPT_EULA=Y" -e 'MSSQL_SA_PASSWORD=SecurePassword123$' \
  --arch amd64 mcr.microsoft.com/mssql/server:2022-latest 2>&1

EXIT_CODE=$?
pkill -P $WD 2>/dev/null; kill $WD 2>/dev/null; wait $WD 2>/dev/null
[ $EXIT_CODE -eq 137 ] && EXIT_CODE=124
echo ""
echo "=== RESULT: ${TEST_NAME} - exit code: ${EXIT_CODE} ==="
exit $EXIT_CODE
