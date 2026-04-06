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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_HELPER="${WORKSPACE_DIR}/scripts/podman-cache-image.sh"
CACHE_DIR="${IMAGE_CACHE_DIR:-${WORKSPACE_DIR}/image-cache}"
CONNECTION_NAME="${CONNECTION#--connection }"
LOGFILE="${TMPDIR:-/tmp}/podman-fex-test-$(date +%Y%m%d_%H%M%S).log"
PASS=0
FAIL=0
RESULTS=()

cache_image() {
  local image="$1"
  local platform="${2:-linux/amd64}"
  if [ ! -x "${CACHE_HELPER}" ]; then
    return 0
  fi
  if [ -n "${CONNECTION_NAME}" ]; then
    "${CACHE_HELPER}" --quiet --connection "${CONNECTION_NAME}" --platform "${platform}" --cache-dir "${CACHE_DIR}" "${image}"
  else
    "${CACHE_HELPER}" --quiet --platform "${platform}" --cache-dir "${CACHE_DIR}" "${image}"
  fi
}

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

if [ -x "${CACHE_HELPER}" ]; then
  echo "Pre-caching docker.io images..."
  for img in \
    "docker.io/library/alpine:latest" \
    "docker.io/library/fedora:latest" \
    "docker.io/library/ubuntu:latest" \
    "docker.io/library/ubuntu:25.10" \
    "docker.io/library/rust:1.93.0-bookworm" \
    "docker.io/library/python:3.11-slim" \
    "docker.io/library/archlinux:latest" \
    "docker.io/library/node:20-slim" \
    "docker.io/library/debian:bookworm-slim" \
    "docker.io/duyquyen/redis-cluster"; do
    echo "  - $img"
    cache_image "$img" linux/amd64
  done
  echo ""
fi

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

  # T10: SWC/Next.js SIGILL (#23269, Rosetta hang → QEMU hang → FEX: was SIGILL, now PASS)
  run_test "T10" "SWC/Next.js (#23269)" \
    "$PODMAN run --rm --platform linux/amd64 node:20-slim bash -c 'cd /tmp && npm init -y >/dev/null 2>&1 && npm install @swc/core >/dev/null 2>&1 && node -e \"const s = require(\\\"@swc/core\\\"); console.log(s.transformSync(\\\"const x: number = 1\\\", {jsc:{parser:{syntax:\\\"typescript\\\"}}}).code)\"'" "EXIT0"

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

  # T12: gawk SIGSEGV (#23219, QEMU SIGSEGV)
  run_test "T12" "gawk (#23219)" \
    "$PODMAN run --rm --platform linux/amd64 debian:bookworm-slim sh -c 'apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq gawk >/dev/null 2>&1 && gawk --version | head -1'" "GNU Awk"

  # T13: redis-cluster SIGSEGV (D#27601, QEMU SIGSEGV)
  run_test "T13" "redis-cluster (D#27601)" \
    "$PODMAN run --rm --platform linux/amd64 docker.io/duyquyen/redis-cluster redis-server --version" "Redis server"

  # T14: su -l login shell (#26656, Rosetta behavioral)
  run_test "T14" "su -l login shell (#26656)" \
    "$PODMAN run --rm --platform linux/amd64 registry.access.redhat.com/ubi8:latest sh -c 'useradd appuser && su -l appuser -c \"shopt -q login_shell && echo Login_shell || echo Not_login_shell\"'" "Login_shell"

  # ── Workload Tests ─────────────────────────────────────
  echo ""
  echo "=================================="
  echo " Workload Tests"
  echo "=================================="

  # T15: dnf install
  run_test "T15" "dnf install git" \
    "$PODMAN run --rm --platform linux/amd64 fedora dnf install -y git" "EXIT0"

  # T16: podman build
  printf "%-4s %-35s " "T16" "podman build x86_64"
  BLDTMP=$(mktemp -d)
  cat > "$BLDTMP/Containerfile" << 'CEOF'
FROM --platform=linux/amd64 alpine:latest
RUN apk add --no-cache curl && curl --version
CEOF
  echo "=== T16: podman build ===" >> "$LOGFILE"
  echo "\$ $PODMAN build --platform linux/amd64 ..." >> "$LOGFILE"
  if $PODMAN build --platform linux/amd64 -f "$BLDTMP/Containerfile" "$BLDTMP" >> "$LOGFILE" 2>&1; then
    echo "✅ PASS"
    RESULTS+=("| T16 | podman build x86_64 | ✅ PASS | |")
    PASS=$((PASS + 1))
  else
    echo "❌ FAIL"
    RESULTS+=("| T16 | podman build x86_64 | ❌ FAIL | |")
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
