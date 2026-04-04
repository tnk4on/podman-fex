#!/usr/bin/env bash
# podman-fex test script
# Usage: ./test.sh [--connection NAME] [--quick]
#   --connection NAME  Use a specific Podman connection (e.g., "fex")
#   --quick            Run only basic tests (T1-T4)
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
RESULTS=()

run_test() {
  local num="$1" name="$2" cmd="$3" expect="$4"
  printf "%-4s %-35s " "$num" "$name"

  echo "=== $num: $name ===" >> "$LOGFILE"
  echo "\$ $cmd" >> "$LOGFILE"
  local output exit_code
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
echo "  Provider: $(podman machine info --format '{{.Host.DefaultMachineProvider}}' 2>/dev/null || echo 'unknown')"
echo ""

# ── Basic Tests ──────────────────────────────────────────
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
printf "%-4s %-35s " "T3" "Stability (5x sequential)"
echo "=== T3: Stability (5x) ===" >> "$LOGFILE"
for i in 1 2 3 4 5; do
  echo "\$ run $i: $PODMAN run --rm --platform linux/amd64 alpine uname -m" >> "$LOGFILE"
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
  RESULTS+=("| T3 | Stability (5x sequential) | ✅ PASS | 5/5 |")
  PASS=$((PASS + 1))
else
  echo "❌ FAIL"
  RESULTS+=("| T3 | Stability (5x sequential) | ❌ FAIL | |")
  FAIL=$((FAIL + 1))
fi

# T4: Multi-distro
printf "%-4s %-35s " "T4" "Multi-distro"
T4_PASS=true
echo "=== T4: Multi-distro ===" >> "$LOGFILE"
for img in fedora ubuntu "registry.access.redhat.com/ubi10/ubi-micro"; do
  echo "\$ $PODMAN run --rm --platform linux/amd64 $img uname -m" >> "$LOGFILE"
  result=$($PODMAN run --rm --platform linux/amd64 "$img" uname -m 2>/dev/null) || true
  echo "$result" >> "$LOGFILE"
  if [ "$result" != "x86_64" ]; then
    T4_PASS=false
    break
  fi
done
echo "" >> "$LOGFILE"
if $T4_PASS; then
  echo "✅ PASS"
  RESULTS+=("| T4 | Multi-distro | ✅ PASS | fedora, ubuntu, ubi10 |")
  PASS=$((PASS + 1))
else
  echo "❌ FAIL (failed on: $img)"
  RESULTS+=("| T4 | Multi-distro | ❌ FAIL | failed on: $img |")
  FAIL=$((FAIL + 1))
fi

if $QUICK; then
  echo ""
  echo "=================================="
  echo " Results (quick mode)"
  echo "=================================="
else
  # ── Issue Reproduction Tests ────────────────────────────
  # Tests from community-reported issues that FEX-Emu fixes.
  # These are the fast-running ones (< 30s each).
  echo ""
  echo "=================================="
  echo " Issue Reproduction Tests"
  echo "=================================="

  # T5: rustc (#28169, QEMU SIGSEGV)
  run_test "T5" "rustc (#28169)" \
    "$PODMAN run --rm --platform linux/amd64 --entrypoint rustc docker.io/library/rust:1.93.0-bookworm -vV" "rustc"

  # T6: PyArrow (#26036, QEMU SIGSEGV)
  run_test "T6" "PyArrow import (#26036)" \
    "$PODMAN run --rm --platform linux/amd64 python:3.11-slim bash -c 'pip install pyarrow==20.0.0 >/dev/null 2>&1 && python -c \"import pyarrow; print(pyarrow.__version__)\"'" "EXIT0"

  # T7: Arch Linux (#27210, Rosetta hang)
  run_test "T7" "Arch Linux (#27210)" \
    "$PODMAN run --rm --platform linux/amd64 archlinux:latest uname -m" "x86_64"

  # T8: Fedora shell (#27817, Rosetta hang)
  run_test "T8" "Fedora shell (#27817)" \
    "$PODMAN run --rm --platform linux/amd64 fedora bash -c 'echo ok'" "ok"

  # T9: Ubuntu (#27799, Rosetta hang)
  run_test "T9" "Ubuntu (#27799)" \
    "$PODMAN run --rm --platform linux/amd64 ubuntu:25.10 uname -m" "x86_64"

  # T10: Angular/Node build hang (#25272, QEMU hang)
  printf "%-4s %-35s " "T10" "Node.js build (#25272)"
  BLDTMP10=$(mktemp -d)
  cat > "$BLDTMP10/Containerfile" << 'CEOF'
FROM --platform=linux/amd64 node:20-alpine3.18
WORKDIR /src
RUN echo '{"name":"test","version":"1.0.0","scripts":{"build":"node -e \"let s=0;for(let i=0;i<1e7;i++)s+=i;console.log(s);\"" }}' > package.json
RUN npm run build
CEOF
  echo "=== T10: Node.js build (#25272) ===" >> "$LOGFILE"
  echo "\$ $PODMAN build --platform linux/amd64 ..." >> "$LOGFILE"
  if $PODMAN build --platform linux/amd64 -f "$BLDTMP10/Containerfile" "$BLDTMP10" >> "$LOGFILE" 2>&1; then
    echo "✅ PASS"
    RESULTS+=("| T10 | Node.js build (#25272) | ✅ PASS | |")
    PASS=$((PASS + 1))
  else
    echo "❌ FAIL"
    RESULTS+=("| T10 | Node.js build (#25272) | ❌ FAIL | |")
    FAIL=$((FAIL + 1))
  fi
  echo "" >> "$LOGFILE"
  rm -rf "$BLDTMP10"

  # T11: sudo BuildKit (#24647, Rosetta nosuid)
  printf "%-4s %-35s " "T11" "sudo in build (#24647)"
  BLDTMP11=$(mktemp -d)
  cat > "$BLDTMP11/Containerfile" << 'CEOF'
FROM --platform=linux/amd64 alpine
RUN apk add shadow sudo
RUN echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers
RUN useradd --create-home --non-unique --uid 1000 --groups wheel user
USER 1000
RUN sudo /bin/ls
CEOF
  echo "=== T11: sudo in build (#24647) ===" >> "$LOGFILE"
  echo "\$ $PODMAN build --platform linux/amd64 ..." >> "$LOGFILE"
  if $PODMAN build --platform linux/amd64 -f "$BLDTMP11/Containerfile" "$BLDTMP11" >> "$LOGFILE" 2>&1; then
    echo "✅ PASS"
    RESULTS+=("| T11 | sudo in build (#24647) | ✅ PASS | |")
    PASS=$((PASS + 1))
  else
    echo "❌ FAIL"
    RESULTS+=("| T11 | sudo in build (#24647) | ❌ FAIL | |")
    FAIL=$((FAIL + 1))
  fi
  echo "" >> "$LOGFILE"
  rm -rf "$BLDTMP11"

  # ── Workload Tests ─────────────────────────────────────
  echo ""
  echo "=================================="
  echo " Workload Tests"
  echo "=================================="

  # T12: dnf install
  run_test "T12" "dnf install git" \
    "$PODMAN run --rm --platform linux/amd64 fedora dnf install -y git" "EXIT0"

  # T13: podman build
  printf "%-4s %-35s " "T13" "podman build x86_64"
  BLDTMP=$(mktemp -d)
  cat > "$BLDTMP/Containerfile" << 'CEOF'
FROM --platform=linux/amd64 alpine:latest
RUN apk add --no-cache curl && curl --version
CEOF
  echo "=== T13: podman build ===" >> "$LOGFILE"
  echo "\$ $PODMAN build --platform linux/amd64 ..." >> "$LOGFILE"
  if $PODMAN build --platform linux/amd64 -f "$BLDTMP/Containerfile" "$BLDTMP" >> "$LOGFILE" 2>&1; then
    echo "✅ PASS"
    RESULTS+=("| T13 | podman build x86_64 | ✅ PASS | |")
    PASS=$((PASS + 1))
  else
    echo "❌ FAIL"
    RESULTS+=("| T13 | podman build x86_64 | ❌ FAIL | |")
    FAIL=$((FAIL + 1))
  fi
  echo "" >> "$LOGFILE"
  rm -rf "$BLDTMP"
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
