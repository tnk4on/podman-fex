#!/usr/bin/env bash
# test-qemu.sh — QEMU-user-static test runner
# 5 categories, 33 tests (infra/basic/issue/workload/stress)
#
# QEMU variant of test-fex.sh — validates x86_64 emulation via qemu-user-static
# on a standard Podman Machine (default Fedora CoreOS image).
#
# Usage:
#   ./test-qemu.sh --connection test-qemu              # default categories
#   ./test-qemu.sh --connection test-qemu --category basic
#   ./test-qemu.sh --connection test-qemu --test I16,B01
#   ./test-qemu.sh --list
set -uo pipefail

# Source shared library
LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${LIB_DIR}/lib-test.sh"

# Default categories (no hook/env — those are FEX-specific)
DEFAULT_CATEGORIES="infra,basic,issue,workload,stress"

show_help() {
  cat <<'EOF'
test-qemu.sh — QEMU-user-static test runner

Options:
  --connection NAME   Podman machine connection
  --machine NAME      Machine name for SSH tests (default: from --connection)
  --category CAT,...  Run specific categories (infra,basic,issue,workload,stress)
  --test ID,...       Run specific tests (e.g., I16,B01)
  --cache-dir DIR     Image cache directory
  --timeout SEC       SSH timeout (default: 30)
  --list              List all tests without running
  -h, --help          Show this help
EOF
}

parse_args "$@"

# If no categories specified, use defaults
[[ -z "$CATEGORIES" && -z "$TESTS" ]] && CATEGORIES="$DEFAULT_CATEGORIES"

LOGFILE="${RESULT_DIR}/test-qemu-$(date +%Y%m%d_%H%M%S).log"
PLATFORM="--platform linux/amd64"
IMG="docker.io/library/alpine:latest"
QEMU_TESTS_DIR="${SCRIPT_DIR}"

# Setup signal traps for graceful interruption
setup_traps

# Log header
_log "QEMU-user-static Test Suite — $(date '+%Y-%m-%d %H:%M:%S')"
_log "Machine: $MACHINE  Connection: ${CONNECTION_NAME:-default}"
_log "Categories: ${CATEGORIES:-all (via --test)}"

# =============================================================================
# Test Registry — list mode
# =============================================================================
print_test_list() {
  cat <<'LIST'
Category  ID     Name
--------  -----  -------------------------------------------
infra     QI01   OS info
infra     QI02   Page size = 4096
infra     QI03   qemu-user-static installed
infra     QI04   QEMU version
infra     QI05   Virtualization type
infra     QI06   binfmt handler registered
infra     QI07   x86_64 handler details
basic     B01    x86_64 container (alpine)
basic     B02    ARM64 regression
basic     B03    Stability (5x sequential)
basic     B04    Multi-distro (fedora/ubuntu/ubi)
issue     I01    gawk SIGSEGV (#23219)
issue     I02    SWC/Next.js SIGILL (#23269)
issue     I03    sudo BuildKit (#24647)
issue     I04    Angular/Node build (#25272)
issue     I05    PyArrow SIGSEGV (#26036)
issue     I06    Express freeze (#26572)
issue     I07    su -l login shell (#26656)
issue     I08    Go hello build (#26881)
issue     I09    Go godump build (#26919)
issue     I10    MSSQL 2022 SIGSEGV (#27078)
issue     I11    Arch Linux hang (#27210)
issue     I12    jemalloc SIGSEGV (#27320)
issue     I13    redis-cluster SIGSEGV (#27601)
issue     I14    Ubuntu hang (#27799)
issue     I15    Fedora hang (#27817)
issue     I16    rustc SIGSEGV (#28169)
issue     I17    MSSQL 2025 AVX (#28184)
workload  W01    dnf install git
workload  W02    podman build x86_64
stress    S01    5 sequential x86_64 containers
stress    S02    CPU workload (dd + md5sum)
stress    S03    Mixed architecture (arm64 + x86_64)
LIST
  echo ""
  echo "Total: 33 tests"
}

if $LIST_ONLY; then
  print_test_list
  exit 0
fi

# =============================================================================
# Pre-flight
# =============================================================================
echo -e "${_C}══════════════════════════════════════════════════${_N}"
echo -e "${_C} QEMU-user-static Test Suite${_N}"
echo -e "${_C}══════════════════════════════════════════════════${_N}"
echo ""
echo "Mode:       standard"
echo "Machine:    $MACHINE"
echo "Connection: ${CONNECTION_NAME:-default}"
echo "Categories: ${CATEGORIES:-all (via --test)}"
[[ -n "$TESTS" ]] && echo "Tests:      $TESTS"
echo ""
echo "Environment:"
echo "  macOS:    $(sw_vers -productVersion 2>/dev/null || echo 'N/A')"
echo "  Chip:     $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'N/A')"
echo "  Podman:   $(podman --version 2>/dev/null || echo 'not found')"
echo ""

# =============================================================================
# Phase 1: infra (7 tests) — VM setup verification (QEMU-specific)
# =============================================================================
run_infra() {
  header "Phase 1: Infrastructure (infra)"
  assert_vm_running

  # QI01: OS info
  run_test "QI01" "OS info" "ssh" \
    "cat /etc/os-release | grep PRETTY_NAME"

  # QI02: Page size
  if test_enabled "QI02"; then
    local page_size
    page_size=$(ssh_cmd "getconf PAGESIZE" || echo "ERROR")
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "QI02" "Page size = 4096"
    if [[ "$page_size" = "4096" ]]; then
      _pass "QI02" "Page size = 4096"
    else
      _fail "QI02" "Page size = 4096" "got: $page_size"
    fi
  fi

  # QI03: qemu-user-static installed
  if test_enabled "QI03"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "QI03" "qemu-user-static installed"
    local qemu_bin
    qemu_bin=$(ssh_cmd "which qemu-x86_64-static 2>/dev/null || ls /usr/bin/qemu-x86_64-static 2>/dev/null || echo MISSING")
    if [[ "$qemu_bin" != "MISSING" && -n "$qemu_bin" ]]; then
      _pass "QI03" "qemu-user-static installed" "$qemu_bin"
    else
      _fail "QI03" "qemu-user-static installed" "not found"
    fi
  fi

  # QI04: QEMU version
  if test_enabled "QI04"; then
    local qemu_ver
    qemu_ver=$(ssh_cmd "qemu-x86_64-static --version 2>/dev/null | head -1" || echo "")
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "QI04" "QEMU version"
    if [[ -n "$qemu_ver" ]]; then
      _pass "QI04" "QEMU version" "$qemu_ver"
    else
      _skip "QI04" "QEMU version" "could not determine"
      TOTAL=$((TOTAL - 1))
    fi
  fi

  # QI05: Virtualization type
  run_test "QI05" "Virtualization type" "ssh" \
    "systemd-detect-virt"

  # QI06: binfmt handler registered
  if test_enabled "QI06"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "QI06" "binfmt x86_64 handler registered"
    local handlers
    handlers=$(ssh_cmd "ls /proc/sys/fs/binfmt_misc/ 2>/dev/null | grep -iE 'qemu.*x86_64|x86_64'" || echo "NONE")
    if [[ "$handlers" != "NONE" && -n "$handlers" ]]; then
      _pass "QI06" "binfmt x86_64 handler registered" "$handlers"
    else
      _fail "QI06" "binfmt x86_64 handler registered" "no x86_64 handler"
    fi
  fi

  # QI07: x86_64 handler details
  if test_enabled "QI07"; then
    local handler_info=""
    for h in qemu-x86_64 qemu-x86_64-static; do
      handler_info=$(ssh_cmd "cat /proc/sys/fs/binfmt_misc/$h 2>/dev/null" || echo "")
      [[ -n "$handler_info" ]] && break
    done
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "QI07" "x86_64 handler details"
    if [[ -n "$handler_info" ]]; then
      local interp
      interp=$(echo "$handler_info" | grep '^interpreter' | awk '{print $2}')
      local flags
      flags=$(echo "$handler_info" | grep '^flags' | awk '{print $2}')
      _pass "QI07" "x86_64 handler details" "interp=$interp flags=$flags"
    else
      _fail "QI07" "x86_64 handler details" "no handler found"
    fi
  fi
}

# =============================================================================
# Phase 2: basic (4 tests) — fundamental emulation (shared with FEX)
# =============================================================================
run_basic() {
  header "Phase 2: Basic Emulation (basic)"

  cache_image "docker.io/library/alpine:latest" "linux/amd64" 2>/dev/null || true
  cache_image "docker.io/library/alpine:latest" "linux/arm64" 2>/dev/null || true

  # B01: x86_64 container
  run_test "B01" "x86_64 container (alpine)" "grep" \
    "$PODMAN run --rm --platform linux/amd64 alpine uname -m" "x86_64"

  # B02: ARM64 regression
  run_test "B02" "ARM64 regression" "grep" \
    "$PODMAN run --rm --platform linux/arm64 alpine uname -m" "aarch64"

  # B03: Stability (5x sequential)
  if test_enabled "B03"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "B03" "Stability (5x sequential)"
    local ok=true
    for i in 1 2 3 4 5; do
      local r
      r=$($PODMAN run --rm --platform linux/amd64 alpine uname -m 2>/dev/null) || true
      [[ "$r" != "x86_64" ]] && { ok=false; break; }
    done
    if $ok; then _pass "B03" "Stability (5x sequential)" "5/5"
    else _fail "B03" "Stability (5x sequential)"; fi
  fi

  # B04: Multi-distro
  if test_enabled "B04"; then
    cache_image "docker.io/library/fedora:latest" "linux/amd64" 2>/dev/null || true
    cache_image "docker.io/library/ubuntu:latest" "linux/amd64" 2>/dev/null || true
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "B04" "Multi-distro (fedora/ubuntu/ubi)"
    local ok=true fail_img=""
    for img in fedora ubuntu "registry.access.redhat.com/ubi10/ubi-micro"; do
      local r
      r=$($PODMAN run --rm --platform linux/amd64 "$img" uname -m 2>/dev/null) || true
      [[ "$r" != "x86_64" ]] && { ok=false; fail_img="$img"; break; }
    done
    if $ok; then _pass "B04" "Multi-distro" "fedora, ubuntu, ubi10"
    else _fail "B04" "Multi-distro" "failed on: $fail_img"; fi
  fi
}

# =============================================================================
# Phase 3: issue (17 tests) — GitHub Issue regression (shared with FEX)
# =============================================================================

# Export pcmd for child scripts
pcmd() {
  if [ -n "${PODMAN_CONNECTION:-}" ]; then
    podman --connection "${PODMAN_CONNECTION}" "$@"
  else
    podman "$@"
  fi
}
export -f pcmd

run_issue_script() {
  local id="$1" name="$2" script="$3" tout="${4:-60}"
  test_enabled "$id" || return 0
  TOTAL=$((TOTAL + 1))
  printf "%-6s %-45s " "$id" "$name"
  _log "=== $id: $name === (script: $script, timeout=${tout}s)"
  local start_time=$(date +%s) output="" exit_code=0
  output=$(PODMAN_CONNECTION="${CONNECTION_NAME}" timeout "$tout" bash "$script" 2>&1) && exit_code=0 || exit_code=$?
  local duration=$(( $(date +%s) - start_time ))
  _log "$output"
  _log "exit_code=$exit_code duration=${duration}s"
  _log ""
  if [[ $exit_code -eq 0 ]]; then
    _pass "$id" "$name" "${duration}s"
  elif [[ $exit_code -eq 124 ]]; then
    echo -e "${_Y}⏱️ TIMEOUT${_N} (${duration}s)"
    _log "  ⏱️ TIMEOUT $id $name (${duration}s)"
    RESULTS+=("$id|$name|TIMEOUT|${duration}s")
    FAIL=$((FAIL + 1))
  else
    _fail "$id" "$name" "exit $exit_code (${duration}s)"
  fi
}

run_issue_build() {
  local id="$1" name="$2" build_dir="$3" tout="${4:-120}"
  test_enabled "$id" || return 0
  TOTAL=$((TOTAL + 1))
  printf "%-6s %-45s " "$id" "$name"
  _log "=== $id: $name === (build: $build_dir, timeout=${tout}s)"
  local start_time=$(date +%s) output="" exit_code=0
  output=$(timeout "$tout" $PODMAN build --platform linux/amd64 -t "qemu-test-$(echo "$id" | tr '[:upper:]' '[:lower:]')" "$build_dir" 2>&1) && exit_code=0 || exit_code=$?
  local duration=$(( $(date +%s) - start_time ))
  _log "$output"
  _log "exit_code=$exit_code duration=${duration}s"
  _log ""
  if [[ $exit_code -eq 0 ]]; then
    _pass "$id" "$name" "${duration}s"
  elif [[ $exit_code -eq 124 ]]; then
    echo -e "${_Y}⏱️ TIMEOUT${_N} (${duration}s)"
    _log "  ⏱️ TIMEOUT $id $name (${duration}s)"
    RESULTS+=("$id|$name|TIMEOUT|${duration}s")
    FAIL=$((FAIL + 1))
  else
    _fail "$id" "$name" "exit $exit_code (${duration}s)"
  fi
}

run_issue() {
  header "Phase 3: Issue Regression (issue)"

  # --- 60s group ---
  run_issue_script "I07" "su -l login shell (#26656)" \
    "${QEMU_TESTS_DIR}/run/16-su-login-shell.sh" 60
  run_issue_build "I09" "Go godump build (#26919)" \
    "${QEMU_TESTS_DIR}/build/13-go-build" 60
  run_issue_script "I11" "Arch Linux hang (#27210)" \
    "${QEMU_TESTS_DIR}/run/06-archlinux.sh" 60
  run_issue_script "I13" "redis-cluster SIGSEGV (#27601)" \
    "${QEMU_TESTS_DIR}/run/14-redis-cluster.sh" 60
  run_issue_script "I14" "Ubuntu hang (#27799)" \
    "${QEMU_TESTS_DIR}/run/08-ubuntu.sh" 60
  run_issue_script "I15" "Fedora hang (#27817)" \
    "${QEMU_TESTS_DIR}/run/07-fedora.sh" 60
  run_issue_script "I16" "rustc SIGSEGV (#28169)" \
    "${QEMU_TESTS_DIR}/run/03-rustc.sh" 60

  # --- 90-120s group ---
  run_issue_script "I02" "SWC/Next.js SIGILL (#23269)" \
    "${QEMU_TESTS_DIR}/run/15-swc-nextjs.sh" 120
  run_issue_build "I03" "sudo BuildKit (#24647)" \
    "${QEMU_TESTS_DIR}/build/11-sudo-buildkit" 120
  run_issue_script "I05" "PyArrow SIGSEGV (#26036)" \
    "${QEMU_TESTS_DIR}/run/04-pyarrow.sh" 90
  run_issue_script "I06" "Express freeze (#26572)" \
    "${QEMU_TESTS_DIR}/run/12-nodejs-express.sh" 120
  run_issue_build "I08" "Go hello build (#26881)" \
    "${QEMU_TESTS_DIR}/build/09-go-hello" 120
  run_issue_script "I10" "MSSQL 2022 SIGSEGV (#27078)" \
    "${QEMU_TESTS_DIR}/run/02-mssql-2022.sh" 120
  run_issue_script "I17" "MSSQL 2025 AVX (#28184)" \
    "${QEMU_TESTS_DIR}/run/01-mssql-2025.sh" 120

  # --- 300-360s group ---
  run_issue_script "I01" "gawk SIGSEGV (#23219)" \
    "${QEMU_TESTS_DIR}/run/13b-gawk.sh" 360
  run_issue_build "I04" "Angular/Node build (#25272)" \
    "${QEMU_TESTS_DIR}/build/10-angular" 300
  run_issue_script "I12" "jemalloc SIGSEGV (#27320)" \
    "${QEMU_TESTS_DIR}/run/05-jemalloc.sh" 360
}

# =============================================================================
# Phase 4: workload (2 tests) — shared with FEX
# =============================================================================
run_workload() {
  header "Phase 4: Workload (workload)"

  cache_image "docker.io/library/fedora:latest" "linux/amd64" 2>/dev/null || true

  # W01: dnf install git
  run_test "W01" "dnf install git" "exit" \
    "$PODMAN run --rm --platform linux/amd64 fedora dnf install -y git"

  # W02: podman build x86_64
  if test_enabled "W02"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "W02" "podman build x86_64"
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/Containerfile" << 'CEOF'
FROM --platform=linux/amd64 alpine:latest
RUN apk add --no-cache curl && curl --version
CEOF
    if $PODMAN build --platform linux/amd64 -f "$tmpdir/Containerfile" "$tmpdir" > /dev/null 2>&1; then
      _pass "W02" "podman build x86_64"
    else
      _fail "W02" "podman build x86_64"
    fi
    rm -rf "$tmpdir"
  fi
}

# =============================================================================
# Phase 5: stress (3 tests) — shared with FEX
# =============================================================================
run_stress() {
  header "Phase 5: Stress Tests (stress)"
  assert_vm_running

  cache_image "docker.io/library/alpine:latest" "linux/amd64" 2>/dev/null || true
  cache_image "docker.io/library/alpine:latest" "linux/arm64" 2>/dev/null || true

  # S01: 5 sequential x86_64 containers
  if test_enabled "S01"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "S01" "5 sequential x86_64 containers"
    local ok=0
    for i in $(seq 1 5); do
      local r
      r=$(timeout "$SSH_TIMEOUT" $PODMAN run --rm --platform linux/amd64 alpine \
        sh -c "echo iteration_$i && uname -m" 2>/dev/null || echo "ERROR")
      echo "$r" | grep -q "x86_64" && ok=$((ok + 1))
    done
    if [[ $ok -eq 5 ]]; then
      _pass "S01" "5 sequential x86_64" "$ok/5"
    else
      _fail "S01" "5 sequential x86_64" "$ok/5 passed"
    fi
  fi

  # S02: CPU workload (dd + md5sum)
  if test_enabled "S02"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "S02" "CPU workload (dd + md5sum)"
    local r
    r=$(timeout 60 $PODMAN run --rm --platform linux/amd64 alpine \
      sh -c "dd if=/dev/zero bs=1M count=100 2>/dev/null | md5sum" 2>&1 || echo "TIMEOUT_OR_ERROR")
    if echo "$r" | grep -q "TIMEOUT_OR_ERROR"; then
      _fail "S02" "CPU workload" "timed out"
    else
      _pass "S02" "CPU workload" "completed"
    fi
  fi

  # S03: Mixed architecture
  if test_enabled "S03"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "S03" "Mixed architecture (arm64 + x86_64)"
    local arm x86
    arm=$(timeout "$SSH_TIMEOUT" $PODMAN run --rm --platform linux/arm64 alpine uname -m 2>/dev/null || echo "ERROR")
    x86=$(timeout "$SSH_TIMEOUT" $PODMAN run --rm --platform linux/amd64 alpine uname -m 2>/dev/null || echo "ERROR")
    if [[ "$arm" = "aarch64" && "$x86" = "x86_64" ]]; then
      _pass "S03" "Mixed architecture" "arm64=$arm, x86=$x86"
    else
      _fail "S03" "Mixed architecture" "arm64=$arm, x86=$x86"
    fi
  fi
}

# =============================================================================
# Main — Execute phases in order
# =============================================================================
category_enabled "infra"    && run_infra
category_enabled "basic"    && run_basic
category_enabled "issue"    && run_issue
category_enabled "workload" && run_workload
category_enabled "stress"   && run_stress

print_summary
exit $?
