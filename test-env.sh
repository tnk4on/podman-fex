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

# ── E1: Code cache enabled + files generated ────────────
# Verify FEX_ENABLECODECACHINGWIP=1 AND actual cache files are created
printf "%-4s %-45s " "E1" "Code cache enabled + files generated"
echo "=== E1: Code cache enabled + files generated ===" >> "$LOGFILE"
CMD_E1="$PODMAN run --rm $PLATFORM $IMG sh -c '
  echo CACHE=\$FEX_ENABLECODECACHINGWIP
  ls / > /dev/null 2>&1
  sleep 2
  CACHE_FILES=\$(find /tmp/fex-data/cache/ -type f 2>/dev/null | wc -l)
  echo CACHE_FILES=\$CACHE_FILES
'"
echo "\$ $CMD_E1" >> "$LOGFILE"
OUTPUT_E1=$(eval "$CMD_E1" 2>&1) && EC_E1=0 || EC_E1=$?
echo "$OUTPUT_E1" >> "$LOGFILE"
echo "exit_code=$EC_E1" >> "$LOGFILE"
echo "" >> "$LOGFILE"
CACHE_VAL=$(echo "$OUTPUT_E1" | grep 'CACHE=' | head -1 | cut -d= -f2)
CACHE_FILES=$(echo "$OUTPUT_E1" | grep 'CACHE_FILES=' | cut -d= -f2 | tr -d ' ')
if [ "$CACHE_VAL" = "1" ] && [ "${CACHE_FILES:-0}" -gt 0 ]; then
  echo "✅ PASS (env=1, ${CACHE_FILES} cache files)"
  RESULTS+=("| E1 | Code cache enabled + files | ✅ PASS | ${CACHE_FILES} cache files |")
  PASS=$((PASS + 1))
else
  echo "❌ FAIL (env=$CACHE_VAL, files=${CACHE_FILES:-0})"
  RESULTS+=("| E1 | Code cache enabled + files | ❌ FAIL | env=$CACHE_VAL files=${CACHE_FILES:-0} |")
  FAIL=$((FAIL + 1))
fi

# ── E2: Code cache disabled via env override ─────────────
run_test "E2" "Code cache disabled (-e ...=0)" \
  "$PODMAN run --rm $PLATFORM -e FEX_ENABLECODECACHINGWIP=0 $IMG sh -c 'echo \$FEX_ENABLECODECACHINGWIP'" \
  'grep -q "0"'

# ── E3: FEX_VERBOSE_CACHE=1 shows cache pipeline ────────
# Run a named container twice with VERBOSE_CACHE=1. The 2nd run shows
# "populated cache" messages proving the cache pipeline is working.
printf "%-4s %-45s " "E3" "Verbose cache pipeline (2-run)"
echo "=== E3: Verbose cache pipeline (2-run) ===" >> "$LOGFILE"
CNT_E3="e3-verbose-$$"
$PODMAN rm -f "$CNT_E3" > /dev/null 2>&1 || true
echo "\$ $PODMAN run --name $CNT_E3 (1st run, cold cache)" >> "$LOGFILE"
$PODMAN run --name "$CNT_E3" $PLATFORM \
  -e FEX_VERBOSE_CACHE=1 -e FEX_SILENTLOG=false -e FEX_OUTPUTLOG=stderr \
  $IMG sh -c 'echo hello' >> "$LOGFILE" 2>&1 || true
echo "" >> "$LOGFILE"
echo "\$ $PODMAN start -a $CNT_E3 (2nd run, warm cache)" >> "$LOGFILE"
OUTPUT_E3=$($PODMAN start -a "$CNT_E3" 2>&1) && EC_E3=0 || EC_E3=$?
echo "$OUTPUT_E3" >> "$LOGFILE"
echo "exit_code=$EC_E3" >> "$LOGFILE"
echo "" >> "$LOGFILE"
$PODMAN rm -f "$CNT_E3" > /dev/null 2>&1 || true
if echo "$OUTPUT_E3" | grep -qi "populated cache\|Compiling code"; then
  echo "✅ PASS (cache pipeline visible)"
  RESULTS+=("| E3 | Verbose cache pipeline | ✅ PASS | cache pipeline messages |")
  PASS=$((PASS + 1))
else
  echo "❌ FAIL (no cache pipeline output)"
  RESULTS+=("| E3 | Verbose cache pipeline | ❌ FAIL | |")
  FAIL=$((FAIL + 1))
fi

# ── E4: Without VERBOSE_CACHE, no pipeline detail ────────
# Same 2-run pattern but WITHOUT FEX_VERBOSE_CACHE.
# The 2nd run should NOT show "populated cache" messages.
printf "%-4s %-45s " "E4" "No verbose cache (control)"
echo "=== E4: No verbose cache (control) ===" >> "$LOGFILE"
CNT_E4="e4-control-$$"
$PODMAN rm -f "$CNT_E4" > /dev/null 2>&1 || true
echo "\$ $PODMAN run --name $CNT_E4 (1st run)" >> "$LOGFILE"
$PODMAN run --name "$CNT_E4" $PLATFORM \
  -e FEX_SILENTLOG=false -e FEX_OUTPUTLOG=stderr \
  $IMG sh -c 'echo hello' >> "$LOGFILE" 2>&1 || true
echo "" >> "$LOGFILE"
echo "\$ $PODMAN start -a $CNT_E4 (2nd run)" >> "$LOGFILE"
OUTPUT_E4=$($PODMAN start -a "$CNT_E4" 2>&1) && EC_E4=0 || EC_E4=$?
echo "$OUTPUT_E4" >> "$LOGFILE"
echo "exit_code=$EC_E4" >> "$LOGFILE"
echo "" >> "$LOGFILE"
$PODMAN rm -f "$CNT_E4" > /dev/null 2>&1 || true
if echo "$OUTPUT_E4" | grep -q "hello" && ! echo "$OUTPUT_E4" | grep -qi "populated cache"; then
  echo "✅ PASS (no pipeline detail)"
  RESULTS+=("| E4 | No verbose cache (control) | ✅ PASS | |")
  PASS=$((PASS + 1))
else
  echo "❌ FAIL"
  RESULTS+=("| E4 | No verbose cache (control) | ❌ FAIL | |")
  FAIL=$((FAIL + 1))
fi

# ── E5: FEX_TSOENABLED=true (verify env accepted) ───────
# TSO enables x86 Total Store Order memory model emulation.
# Effect is internal to FEX JIT; verify env is passed and accepted.
run_test "E5" "TSO enabled (env=true)" \
  "$PODMAN run --rm $PLATFORM -e FEX_TSOENABLED=true $IMG sh -c 'echo TSO=\$FEX_TSOENABLED; uname -m'" \
  'grep -q "TSO=true"'

# ── E6: FEX_TSOENABLED=false (verify env accepted) ──────
# TSO disabled: single-threaded workloads still work correctly.
run_test "E6" "TSO disabled (env=false)" \
  "$PODMAN run --rm $PLATFORM -e FEX_TSOENABLED=false $IMG sh -c 'echo TSO=\$FEX_TSOENABLED; uname -m'" \
  'grep -q "TSO=false"'

# ── E7: FEX_SILENTLOG=false shows FEX debug log ─────────
# SILENTLOG=false + OUTPUTLOG=stderr → FEX debug lines ("D ...") visible.
printf "%-4s %-45s " "E7" "FEX log visible (SILENTLOG=false)"
echo "=== E7: FEX_SILENTLOG=false + OUTPUTLOG=stderr ===" >> "$LOGFILE"
CMD_E7="$PODMAN run --rm $PLATFORM -e FEX_SILENTLOG=false -e FEX_OUTPUTLOG=stderr $IMG uname -m 2>&1"
echo "\$ $CMD_E7" >> "$LOGFILE"
OUTPUT_E7=$(eval "$CMD_E7") && EC_E7=0 || EC_E7=$?
echo "$OUTPUT_E7" >> "$LOGFILE"
echo "exit_code=$EC_E7" >> "$LOGFILE"
echo "" >> "$LOGFILE"
LINE_COUNT_E7=$(echo "$OUTPUT_E7" | wc -l | tr -d ' ')
if echo "$OUTPUT_E7" | grep -q "x86_64" && echo "$OUTPUT_E7" | grep -q "^D "; then
  echo "✅ PASS (${LINE_COUNT_E7} lines, debug visible)"
  RESULTS+=("| E7 | FEX log visible | ✅ PASS | ${LINE_COUNT_E7} lines, D prefix |")
  PASS=$((PASS + 1))
else
  echo "❌ FAIL (expected debug output)"
  RESULTS+=("| E7 | FEX log visible | ❌ FAIL | ${LINE_COUNT_E7} lines |")
  FAIL=$((FAIL + 1))
fi

# ── E8: Default log behavior (silent, clean output) ──────
# Without explicit SILENTLOG/OUTPUTLOG, FEX is silent by default.
printf "%-4s %-45s " "E8" "Default log silent (clean output)"
echo "=== E8: Default log (silent) ===" >> "$LOGFILE"
CMD_E8="$PODMAN run --rm $PLATFORM $IMG sh -c 'echo hello' 2>&1"
echo "\$ $CMD_E8" >> "$LOGFILE"
OUTPUT_E8=$(eval "$CMD_E8") && EC_E8=0 || EC_E8=$?
echo "$OUTPUT_E8" >> "$LOGFILE"
echo "exit_code=$EC_E8" >> "$LOGFILE"
echo "" >> "$LOGFILE"
# Default: no "D" debug lines, just the command output
if echo "$OUTPUT_E8" | grep -q "hello" && ! echo "$OUTPUT_E8" | grep -q "^D "; then
  echo "✅ PASS (clean output, no debug)"
  RESULTS+=("| E8 | Default log silent | ✅ PASS | clean output |")
  PASS=$((PASS + 1))
else
  echo "❌ FAIL (unexpected debug output)"
  RESULTS+=("| E8 | Default log silent | ❌ FAIL | debug lines present |")
  FAIL=$((FAIL + 1))
fi

# ── E9: FEX_MULTIBLOCK=true (verify env accepted) ───────
# Multiblock JIT compiles multiple basic blocks together for better perf.
run_test "E9" "Multiblock JIT enabled (env=true)" \
  "$PODMAN run --rm $PLATFORM -e FEX_MULTIBLOCK=true $IMG sh -c 'echo MULTIBLOCK=\$FEX_MULTIBLOCK; uname -m'" \
  'grep -q "MULTIBLOCK=true"'

# ── E10: FEX_MULTIBLOCK=false (verify env accepted) ──────
# Disabling multiblock falls back to single-block JIT (slower).
run_test "E10" "Multiblock JIT disabled (env=false)" \
  "$PODMAN run --rm $PLATFORM -e FEX_MULTIBLOCK=false $IMG sh -c 'echo MULTIBLOCK=\$FEX_MULTIBLOCK; uname -m'" \
  'grep -q "MULTIBLOCK=false"'

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

# ── E14: All env sources combined ────────────────────────
# Verify that OCI hook, containers.conf, and user -e vars coexist.
printf "%-4s %-45s " "E14" "All env sources combined"
echo "=== E14: All env sources combined ===" >> "$LOGFILE"
CMD_E14="$PODMAN run --rm $PLATFORM -e FEX_TSOENABLED=false -e FEX_MULTIBLOCK=false $IMG sh -c 'env | grep FEX | sort'"
echo "\$ $CMD_E14" >> "$LOGFILE"
OUTPUT_E14=$(eval "$CMD_E14" 2>&1) && EC_E14=0 || EC_E14=$?
echo "$OUTPUT_E14" >> "$LOGFILE"
echo "exit_code=$EC_E14" >> "$LOGFILE"
echo "" >> "$LOGFILE"
# Check: hook vars (APP_DATA), containers.conf (ENABLECODECACHINGWIP), user -e (TSOENABLED, MULTIBLOCK)
HAS_HOOK=$(echo "$OUTPUT_E14" | grep -c "FEX_APP_DATA_LOCATION")
HAS_CONF=$(echo "$OUTPUT_E14" | grep -c "FEX_ENABLECODECACHINGWIP")
HAS_TSO=$(echo "$OUTPUT_E14" | grep -c "FEX_TSOENABLED=false")
HAS_MB=$(echo "$OUTPUT_E14" | grep -c "FEX_MULTIBLOCK=false")
if [ "$HAS_HOOK" -ge 1 ] && [ "$HAS_CONF" -ge 1 ] && [ "$HAS_TSO" -ge 1 ] && [ "$HAS_MB" -ge 1 ]; then
  echo "✅ PASS (hook + conf + user-e)"
  RESULTS+=("| E14 | All env sources combined | ✅ PASS | hook + conf + user-e |")
  PASS=$((PASS + 1))
else
  echo "❌ FAIL (missing: hook=$HAS_HOOK conf=$HAS_CONF tso=$HAS_TSO mb=$HAS_MB)"
  RESULTS+=("| E14 | All env sources combined | ❌ FAIL | |")
  FAIL=$((FAIL + 1))
fi

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
