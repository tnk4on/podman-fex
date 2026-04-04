#!/usr/bin/env bash
# FEX-Emu environment variable tests for podman-fex
# Usage: ./test-env.sh [--connection NAME]
#   --connection NAME  Use a specific Podman connection (e.g., "fex")
set -euo pipefail

CONNECTION=""
for arg in "$@"; do
  case "$arg" in
    --connection)  shift; CONNECTION="--connection $1"; shift ;;
    --connection=*) CONNECTION="--connection ${arg#*=}" ;;
  esac
done

PODMAN="podman $CONNECTION"
LOGFILE="${TMPDIR:-/tmp}/podman-fex-env-test-$(date +%Y%m%d_%H%M%S).log"
PASS=0
FAIL=0
RESULTS=()

IMG="alpine"
PLATFORM="--platform linux/amd64"

run_test() {
  local num="$1" name="$2" cmd="$3" check_fn="$4"
  printf "%-4s %-45s " "$num" "$name"

  echo "=== $num: $name ===" >> "$LOGFILE"
  echo "\$ $cmd" >> "$LOGFILE"
  local output exit_code
  output=$(eval "$cmd" 2>&1) && exit_code=0 || exit_code=$?
  echo "$output" >> "$LOGFILE"
  echo "exit_code=$exit_code" >> "$LOGFILE"
  echo "" >> "$LOGFILE"

  if eval "$check_fn" <<< "$output"; then
    echo "✅ PASS"
    RESULTS+=("| $num | $name | ✅ PASS | |")
    PASS=$((PASS + 1))
  else
    echo "❌ FAIL (exit=$exit_code, got: $(echo "$output" | tail -1 | head -c 60))"
    RESULTS+=("| $num | $name | ❌ FAIL | exit=$exit_code |")
    FAIL=$((FAIL + 1))
  fi
}

echo "=========================================="
echo " FEX-Emu Environment Variable Tests"
echo "=========================================="
echo ""
echo "Environment:"
echo "  macOS:    $(sw_vers -productVersion)"
echo "  Chip:     $(sysctl -n machdep.cpu.brand_string)"
echo "  Podman:   $(podman --version 2>/dev/null || echo 'not found')"
echo ""

# ── E1: Code cache enabled (default) ────────────────────
# Verify the default containers.conf injects FEX_ENABLECODECACHINGWIP=1
run_test "E1" "Code cache enabled (default)" \
  "$PODMAN run --rm $PLATFORM $IMG sh -c 'echo \$FEX_ENABLECODECACHINGWIP'" \
  'grep -q "1"'

# ── E2: Code cache disabled via env override ─────────────
run_test "E2" "Code cache disabled (-e ...=0)" \
  "$PODMAN run --rm $PLATFORM -e FEX_ENABLECODECACHINGWIP=0 $IMG sh -c 'echo \$FEX_ENABLECODECACHINGWIP'" \
  'grep -q "0"'

# ── E3: FEX_VERBOSE_CACHE=1 accepted without error ──────
# Verbose cache logs are emitted by FEXServer (not container stderr),
# so we verify the variable is accepted and execution succeeds.
run_test "E3" "Verbose cache env accepted (=1)" \
  "$PODMAN run --rm $PLATFORM -e FEX_VERBOSE_CACHE=1 $IMG sh -c 'echo hello'" \
  'grep -q "hello"'

# ── E4: FEX_VERBOSE_CACHE=0 suppresses cache log ────────
printf "%-4s %-45s " "E4" "Verbose cache off (=0, no extra log)"
echo "=== E4: Verbose cache off ===" >> "$LOGFILE"
CMD_E4="$PODMAN run --rm $PLATFORM -e FEX_VERBOSE_CACHE=0 $IMG sh -c 'echo hello' 2>&1"
echo "\$ $CMD_E4" >> "$LOGFILE"
OUTPUT_E4=$(eval "$CMD_E4") && EC_E4=0 || EC_E4=$?
echo "$OUTPUT_E4" >> "$LOGFILE"
echo "exit_code=$EC_E4" >> "$LOGFILE"
echo "" >> "$LOGFILE"
# Should have "hello" but no cache log lines
if echo "$OUTPUT_E4" | grep -q "hello"; then
  # Count lines — should be minimal (just "hello" and maybe a blank)
  LINE_COUNT=$(echo "$OUTPUT_E4" | wc -l | tr -d ' ')
  if [ "$LINE_COUNT" -le 3 ]; then
    echo "✅ PASS (${LINE_COUNT} lines)"
    RESULTS+=("| E4 | Verbose cache off (=0) | ✅ PASS | ${LINE_COUNT} lines |")
    PASS=$((PASS + 1))
  else
    echo "❌ FAIL (${LINE_COUNT} lines, expected ≤3)"
    RESULTS+=("| E4 | Verbose cache off (=0) | ❌ FAIL | ${LINE_COUNT} lines |")
    FAIL=$((FAIL + 1))
  fi
else
  echo "❌ FAIL (no 'hello' in output)"
  RESULTS+=("| E4 | Verbose cache off (=0) | ❌ FAIL | no output |")
  FAIL=$((FAIL + 1))
fi

# ── E5: FEX_TSOENABLED=true (default) ───────────────────
# TSO enabled should not break basic execution
run_test "E5" "TSO enabled (default)" \
  "$PODMAN run --rm $PLATFORM -e FEX_TSOENABLED=true $IMG uname -m" \
  'grep -q "x86_64"'

# ── E6: FEX_TSOENABLED=false ─────────────────────────────
# TSO disabled should still allow basic single-threaded execution
run_test "E6" "TSO disabled" \
  "$PODMAN run --rm $PLATFORM -e FEX_TSOENABLED=false $IMG uname -m" \
  'grep -q "x86_64"'

# ── E7: FEX_SILENTLOG=false shows FEX log ───────────────
printf "%-4s %-45s " "E7" "Silent log off (FEX log visible)"
echo "=== E7: FEX_SILENTLOG=false ===" >> "$LOGFILE"
CMD_E7="$PODMAN run --rm $PLATFORM -e FEX_SILENTLOG=false -e FEX_OUTPUTLOG=stderr $IMG uname -m 2>&1"
echo "\$ $CMD_E7" >> "$LOGFILE"
OUTPUT_E7=$(eval "$CMD_E7") && EC_E7=0 || EC_E7=$?
echo "$OUTPUT_E7" >> "$LOGFILE"
echo "exit_code=$EC_E7" >> "$LOGFILE"
echo "" >> "$LOGFILE"
# With silent log off and output to stderr, we expect more output than just "x86_64"
LINE_COUNT_E7=$(echo "$OUTPUT_E7" | wc -l | tr -d ' ')
if echo "$OUTPUT_E7" | grep -q "x86_64" && [ "$LINE_COUNT_E7" -gt 1 ]; then
  echo "✅ PASS (${LINE_COUNT_E7} lines)"
  RESULTS+=("| E7 | Silent log off | ✅ PASS | ${LINE_COUNT_E7} lines of output |")
  PASS=$((PASS + 1))
else
  echo "❌ FAIL (expected log output, got ${LINE_COUNT_E7} lines)"
  RESULTS+=("| E7 | Silent log off | ❌ FAIL | ${LINE_COUNT_E7} lines |")
  FAIL=$((FAIL + 1))
fi

# ── E8: FEX_SILENTLOG=true (default, minimal output) ────
printf "%-4s %-45s " "E8" "Silent log on (default, quiet)"
echo "=== E8: FEX_SILENTLOG=true ===" >> "$LOGFILE"
CMD_E8="$PODMAN run --rm $PLATFORM -e FEX_SILENTLOG=true $IMG sh -c 'echo hello' 2>&1"
echo "\$ $CMD_E8" >> "$LOGFILE"
OUTPUT_E8=$(eval "$CMD_E8") && EC_E8=0 || EC_E8=$?
echo "$OUTPUT_E8" >> "$LOGFILE"
echo "exit_code=$EC_E8" >> "$LOGFILE"
echo "" >> "$LOGFILE"
LINE_COUNT_E8=$(echo "$OUTPUT_E8" | wc -l | tr -d ' ')
if echo "$OUTPUT_E8" | grep -q "hello" && [ "$LINE_COUNT_E8" -le 3 ]; then
  echo "✅ PASS (${LINE_COUNT_E8} lines)"
  RESULTS+=("| E8 | Silent log on (default) | ✅ PASS | ${LINE_COUNT_E8} lines |")
  PASS=$((PASS + 1))
else
  echo "❌ FAIL (got ${LINE_COUNT_E8} lines)"
  RESULTS+=("| E8 | Silent log on (default) | ❌ FAIL | ${LINE_COUNT_E8} lines |")
  FAIL=$((FAIL + 1))
fi

# ── E9: FEX_MULTIBLOCK=true (default) ───────────────────
run_test "E9" "Multiblock JIT (default=true)" \
  "$PODMAN run --rm $PLATFORM -e FEX_MULTIBLOCK=true $IMG uname -m" \
  'grep -q "x86_64"'

# ── E10: FEX_MULTIBLOCK=false ────────────────────────────
run_test "E10" "Multiblock JIT disabled" \
  "$PODMAN run --rm $PLATFORM -e FEX_MULTIBLOCK=false $IMG uname -m" \
  'grep -q "x86_64"'

# ── E11: OCI hook sets FEX_APP_DATA_LOCATION ─────────────
run_test "E11" "OCI hook: FEX_APP_DATA_LOCATION" \
  "$PODMAN run --rm $PLATFORM $IMG sh -c 'echo \$FEX_APP_DATA_LOCATION'" \
  'grep -q "/tmp/fex-data/"'

# ── E12: OCI hook sets FEX_APP_CONFIG_LOCATION ───────────
run_test "E12" "OCI hook: FEX_APP_CONFIG_LOCATION" \
  "$PODMAN run --rm $PLATFORM $IMG sh -c 'echo \$FEX_APP_CONFIG_LOCATION'" \
  'grep -q "/tmp/fex-data/"'

# ── E13: OCI hook sets FEX_APP_CACHE_LOCATION ────────────
run_test "E13" "OCI hook: FEX_APP_CACHE_LOCATION" \
  "$PODMAN run --rm $PLATFORM $IMG sh -c 'echo \$FEX_APP_CACHE_LOCATION'" \
  'grep -q "/tmp/fex-data/cache/"'

# ── E14: OCI hook env takes precedence over -e override ──
# The OCI precreate hook appends FEX_APP_DATA_LOCATION after user -e,
# so the hook value wins. This verifies the hook value is present.
run_test "E14" "OCI hook env precedence" \
  "$PODMAN run --rm $PLATFORM -e FEX_APP_DATA_LOCATION=/tmp/custom-fex/ $IMG sh -c 'echo \$FEX_APP_DATA_LOCATION'" \
  'grep -q "/tmp/fex-data/"'

# ── E15: ARM64 container has no FEX env vars ─────────────
printf "%-4s %-45s " "E15" "ARM64: no FEX env vars injected"
echo "=== E15: ARM64 no FEX env ===" >> "$LOGFILE"
CMD_E15="$PODMAN run --rm --platform linux/arm64 $IMG sh -c 'echo DATA=\$FEX_APP_DATA_LOCATION CONFIG=\$FEX_APP_CONFIG_LOCATION CACHE=\$FEX_APP_CACHE_LOCATION' 2>&1"
echo "\$ $CMD_E15" >> "$LOGFILE"
OUTPUT_E15=$(eval "$CMD_E15") && EC_E15=0 || EC_E15=$?
echo "$OUTPUT_E15" >> "$LOGFILE"
echo "exit_code=$EC_E15" >> "$LOGFILE"
echo "" >> "$LOGFILE"
# ARM64 should NOT have OCI hook env vars (all empty)
if echo "$OUTPUT_E15" | grep -q "DATA= CONFIG= CACHE="; then
  echo "✅ PASS (no FEX env vars)"
  RESULTS+=("| E15 | ARM64: no FEX env vars | ✅ PASS | |")
  PASS=$((PASS + 1))
else
  echo "❌ FAIL (FEX vars present in ARM64)"
  RESULTS+=("| E15 | ARM64: no FEX env vars | ❌ FAIL | vars present |")
  FAIL=$((FAIL + 1))
fi

# ── Summary ──────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
echo ""
echo "=========================================="
echo " Summary: $PASS/$TOTAL passed"
echo "=========================================="
echo ""
echo "| Test | Name | Result | Notes |"
echo "|------|------|:------:|-------|"
for r in "${RESULTS[@]}"; do
  echo "$r"
done
echo ""
echo "Full log: $LOGFILE"
