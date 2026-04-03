#!/usr/bin/env bash
# podman-fex test script
# Usage: ./test.sh [--connection NAME] [--quick]
#   --connection NAME  Use a specific Podman connection (e.g., "fex")
#   --quick            Run only basic tests (T1-T5)
set -euo pipefail

CONNECTION=""
QUICK=false
for arg in "$@"; do
  case "$arg" in
    --connection)  shift; CONNECTION="--connection $1"; shift ;;
    --connection=*) CONNECTION="--connection ${arg#*=}" ;;
    --quick) QUICK=true ;;
  esac
done

PODMAN="podman $CONNECTION"
LOGFILE="${TMPDIR:-/tmp}/podman-fex-test-$(date +%Y%m%d_%H%M%S).log"
PASS=0
FAIL=0
SKIP=0
RESULTS=()

# Write raw command output to log file
log_cmd() {
  local label="$1"
  shift
  echo "=== $label ===" >> "$LOGFILE"
  echo "\$ $*" >> "$LOGFILE"
  eval "$@" >> "$LOGFILE" 2>&1 && local rc=0 || local rc=$?
  echo "exit_code=$rc" >> "$LOGFILE"
  echo "" >> "$LOGFILE"
  return $rc
}

run_test() {
  local num="$1" name="$2" cmd="$3" expect="$4"
  printf "%-4s %-30s " "$num" "$name"

  local output exit_code
  echo "=== $num: $name ===" >> "$LOGFILE"
  echo "\$ $cmd" >> "$LOGFILE"
  output=$(eval "$cmd" 2>&1) && exit_code=0 || exit_code=$?
  echo "$output" >> "$LOGFILE"
  echo "exit_code=$exit_code" >> "$LOGFILE"
  echo "" >> "$LOGFILE"

  if [ "$expect" = "EXIT0" ]; then
    if [ "$exit_code" -eq 0 ]; then
      echo "✅ PASS"
      RESULTS+=("| $num | $name | ✅ PASS | |")
      PASS=$((PASS + 1))
    else
      echo "❌ FAIL (exit $exit_code)"
      RESULTS+=("| $num | $name | ❌ FAIL | exit $exit_code |")
      FAIL=$((FAIL + 1))
    fi
  elif echo "$output" | grep -q "$expect"; then
    echo "✅ PASS"
    RESULTS+=("| $num | $name | ✅ PASS | |")
    PASS=$((PASS + 1))
  else
    echo "❌ FAIL (got: $(echo "$output" | tail -1 | head -c 60))"
    RESULTS+=("| $num | $name | ❌ FAIL | $(echo "$output" | tail -1 | head -c 60) |")
    FAIL=$((FAIL + 1))
  fi
}

echo "=================================="
echo " podman-fex Test Suite"
echo "=================================="
echo ""
echo "Environment:"
echo "  macOS:    $(sw_vers -productVersion)"
echo "  Chip:     $(sysctl -n machdep.cpu.brand_string)"
echo "  Podman:   $(podman --version 2>/dev/null || echo 'not found')"
echo "  Machine:  $($PODMAN machine info --format '{{.Host.CurrentMachine}}' 2>/dev/null || echo 'unknown')"
echo ""
echo "=================================="
echo " Basic Tests"
echo "=================================="

# T1: x86_64 container
run_test "T1" "x86_64 container" \
  "$PODMAN run --rm --platform linux/amd64 alpine uname -m" "x86_64"

# T2: ARM64 regression
run_test "T2" "ARM64 regression" \
  "$PODMAN run --rm --platform linux/arm64 alpine uname -m" "aarch64"

# T3: Stability (5x)
T3_PASS=true
printf "%-4s %-30s " "T3" "Stability (5x)"
echo "=== T3: Stability (5x) ===" >> "$LOGFILE"
for i in 1 2 3 4 5; do
  echo "\$ $PODMAN run --rm --platform linux/amd64 alpine uname -m (run $i)" >> "$LOGFILE"
  result=$($PODMAN run --rm --platform linux/amd64 alpine uname -m 2>/dev/null) || true
  echo "$result" >> "$LOGFILE"
  if [ "$result" != "x86_64" ]; then
    T3_PASS=false
    break
  fi
done
echo "" >> "$LOGFILE"
if $T3_PASS; then
  echo "✅ PASS (5/5)"
  RESULTS+=("| T3 | Stability (5x) | ✅ PASS | 5/5 |")
  PASS=$((PASS + 1))
else
  echo "❌ FAIL"
  RESULTS+=("| T3 | Stability (5x) | ❌ FAIL | |")
  FAIL=$((FAIL + 1))
fi

# T4: Fedora x86_64
run_test "T4" "Fedora x86_64" \
  "$PODMAN run --rm --platform linux/amd64 fedora uname -m" "x86_64"

# T5: UBI10 + dnf
run_test "T5" "UBI10 + dnf" \
  "$PODMAN run --rm --platform linux/amd64 registry.access.redhat.com/ubi10/ubi dnf --version" "EXIT0"

if $QUICK; then
  echo ""
  echo "=================================="
  echo " Results (quick mode)"
  echo "=================================="
else
  echo ""
  echo "=================================="
  echo " Real-World Tests"
  echo "=================================="

  # T6: dnf install
  run_test "T6" "dnf install git" \
    "$PODMAN run --rm --platform linux/amd64 fedora dnf install -y git" "EXIT0"

  # T7: Python pip
  run_test "T7" "Python pip install" \
    "$PODMAN run --rm --platform linux/amd64 python:3.11-slim pip install requests" "EXIT0"

  # T8: Node.js
  run_test "T8" "Node.js hello" \
    "$PODMAN run --rm --platform linux/amd64 node:20-slim node -e \"console.log('hello')\"" "hello"

  # T9: podman build
  printf "%-4s %-30s " "T9" "podman build"
  BLDTMP=$(mktemp -d)
  cat > "$BLDTMP/Containerfile" << 'CEOF'
FROM --platform=linux/amd64 alpine:latest
RUN apk add --no-cache curl && curl --version
CEOF
  echo "=== T9: podman build ===" >> "$LOGFILE"
  echo "\$ $PODMAN build --platform linux/amd64 -f $BLDTMP/Containerfile $BLDTMP" >> "$LOGFILE"
  if $PODMAN build --platform linux/amd64 -f "$BLDTMP/Containerfile" "$BLDTMP" >> "$LOGFILE" 2>&1; then
    echo "✅ PASS"
    RESULTS+=("| T9 | podman build | ✅ PASS | |")
    PASS=$((PASS + 1))
  else
    echo "❌ FAIL"
    RESULTS+=("| T9 | podman build | ❌ FAIL | |")
    FAIL=$((FAIL + 1))
  fi
  echo "" >> "$LOGFILE"
  rm -rf "$BLDTMP"

  # T10: rustc
  run_test "T10" "rustc version" \
    "$PODMAN run --rm --platform linux/amd64 rust:latest rustc --version" "rustc"

  echo ""
  echo "=================================="
  echo " Additional Tests"
  echo "=================================="

  # T11: Heavy build
  run_test "T11" "Fedora gcc+make install" \
    "$PODMAN run --rm --platform linux/amd64 fedora bash -c 'dnf install -y gcc make && echo done'" "done"

  # T12: Long loop
  run_test "T12" "Loop 1-100" \
    "$PODMAN run --rm --platform linux/amd64 alpine sh -c 'for i in \$(seq 1 100); do echo \$i; done'" "100"

  # T13: Multi-distro
  printf "%-4s %-30s " "T13" "Multi-distro (4 images)"
  T13_PASS=true
  echo "=== T13: Multi-distro ===" >> "$LOGFILE"
  for img in alpine fedora ubuntu "registry.access.redhat.com/ubi10/ubi-micro"; do
    echo "\$ $PODMAN run --rm --platform linux/amd64 $img uname -m" >> "$LOGFILE"
    result=$($PODMAN run --rm --platform linux/amd64 "$img" uname -m 2>/dev/null) || true
    echo "$result" >> "$LOGFILE"
    if [ "$result" != "x86_64" ]; then
      T13_PASS=false
      break
    fi
  done
  echo "" >> "$LOGFILE"
  if $T13_PASS; then
    echo "✅ PASS"
    RESULTS+=("| T13 | Multi-distro | ✅ PASS | alpine, fedora, ubuntu, ubi10 |")
    PASS=$((PASS + 1))
  else
    echo "❌ FAIL (failed on: $img)"
    RESULTS+=("| T13 | Multi-distro | ❌ FAIL | failed on: $img |")
    FAIL=$((FAIL + 1))
  fi
fi

TOTAL=$((PASS + FAIL))
echo ""
echo "=================================="
echo " Summary: $PASS/$TOTAL passed"
echo "=================================="
echo ""
echo "| Test | Name | Result | Notes |"
echo "|------|------|:------:|-------|"
for r in "${RESULTS[@]}"; do
  echo "$r"
done
echo ""
echo "Environment: macOS $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string), $(podman --version 2>/dev/null)"
echo ""
echo "Full log: $LOGFILE"
