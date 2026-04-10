#!/usr/bin/env bash
# test-fex.sh — FEX-Emu unified test runner
# 7 categories, 52 tests (infra/basic/hook/env/issue/workload/stress)
#
# Usage:
#   ./test-fex.sh --connection test                    # default categories
#   ./test-fex.sh --connection test --category basic   # basic only
#   ./test-fex.sh --connection test --mode both        # run rootless + rootful
#   ./test-fex.sh --connection test --test I16,B01     # specific tests
#   ./test-fex.sh --list                               # list all tests
set -uo pipefail

# Source shared library
LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${LIB_DIR}/lib-test.sh"

# Default categories (when no --category specified)
DEFAULT_CATEGORIES="infra,basic,hook,env,issue,workload,stress"

show_help() {
  cat <<'EOF'
test-fex.sh — FEX-Emu unified test runner

Options:
  --connection NAME   Podman machine connection
  --machine NAME      Machine name for SSH tests (default: from --connection)
  --mode MODE         Test mode: rootless|rootful|both (default: rootless)
  --rootful-connection NAME
                      Rootful connection for --mode both (default: <connection>-root)
  --category CAT,...  Run specific categories (infra,basic,hook,env,issue,workload,stress)
  --test ID,...       Run specific tests (e.g., I16,B01,E01)
  --cache-dir DIR     Image cache directory
  --timeout SEC       SSH timeout (default: 30)
  --list              List all tests without running
  -h, --help          Show this help
EOF
}

parse_args "$@"

# If no categories specified, use defaults
[[ -z "$CATEGORIES" && -z "$TESTS" ]] && CATEGORIES="$DEFAULT_CATEGORIES"

# Dual-mode orchestrator: run the same test selection in rootless and rootful.
if [[ "$TEST_MODE" == "both" ]]; then
  if [[ -z "$CONNECTION_NAME" ]]; then
    echo "ERROR: --mode both requires --connection"
    exit 1
  fi

  ROOTLESS_CONNECTION="$CONNECTION_NAME"
  ROOTFUL_CONNECTION="${ROOTFUL_CONNECTION_NAME:-${ROOTLESS_CONNECTION}-root}"

  COMMON_ARGS=(--machine "$MACHINE" --timeout "$SSH_TIMEOUT" --cache-dir "$CACHE_DIR")
  [[ -n "$CATEGORIES" ]] && COMMON_ARGS+=(--category "$CATEGORIES")
  [[ -n "$TESTS" ]] && COMMON_ARGS+=(--test "$TESTS")

  echo "Dual mode run"
  echo "  Rootless connection: $ROOTLESS_CONNECTION"
  echo "  Rootful connection:  $ROOTFUL_CONNECTION"
  echo ""

  "$0" --mode rootless --connection "$ROOTLESS_CONNECTION" "${COMMON_ARGS[@]}"
  RC_ROOTLESS=$?

  "$0" --mode rootful --connection "$ROOTFUL_CONNECTION" "${COMMON_ARGS[@]}"
  RC_ROOTFUL=$?

  echo ""
  echo "Dual mode summary: rootless=$RC_ROOTLESS rootful=$RC_ROOTFUL"
  [[ $RC_ROOTLESS -eq 0 && $RC_ROOTFUL -eq 0 ]] && exit 0 || exit 1
fi

LOGFILE="${RESULT_DIR}/test-fex-${TEST_MODE}-$(date +%Y%m%d_%H%M%S).log"
PLATFORM="--platform linux/amd64"
IMG="docker.io/library/alpine:latest"
FEX_TESTS_DIR="${SCRIPT_DIR}"

# Setup signal traps for graceful interruption
setup_traps

# Log header
_log "FEX-Emu Test Suite — $(date '+%Y-%m-%d %H:%M:%S')"
_log "Machine: $MACHINE  Connection: ${CONNECTION_NAME:-default}"
_log "Categories: ${CATEGORIES:-all (via --test)}"

# =============================================================================
# Test Registry — list mode
# =============================================================================
print_test_list() {
  cat <<'LIST'
Category  ID     Name
--------  -----  -------------------------------------------
infra     INF01  OS info                                      
infra     INF02  Page size = 4096                             
infra     INF03  FEXInterpreter installed                     
infra     INF04  FEX version                                  
infra     INF05  FEX RootFS found                             
infra     INF06  Virtualization type = vm-other               
infra     INF07  binfmt handler registered                    
infra     INF08  x86_64 handler details                       
infra     INF09  x86 (32-bit) handler details                 
infra     INF10  QEMU handler status                          
basic     B01    x86_64 container (alpine)                    
basic     B02    ARM64 regression                             
basic     B03    Stability (5x sequential)                    
basic     B04    Multi-distro (fedora/ubuntu/ubi)             
hook      H01    FEX bind mounts in amd64 (>=5)              
hook      H02    All FEX mounts read-only                     
hook      H03    No FEX in arm64 container                    
hook      H04    FEX RootFS mount type = erofs               
hook      H05    Code cache env = 1                           
env       E01    Code cache enabled + files generated         
env       E02    Code cache disabled (env override)           
env       E03    Verbose cache pipeline (2-run)               
env       E04    No verbose cache (control)                   
env       E07    FEX log visible (SILENTLOG=false)           
env       E08    Default log silent (clean output)            
env       E11    OCI hook: FEX_APP_DATA_LOCATION             
env       E12    OCI hook: FEX_APP_CONFIG_LOCATION           
env       E13    OCI hook: FEX_APP_CACHE_LOCATION            
env       E14    All env sources combined                     
env       E15    ARM64: no FEX bind mounts                   
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
  echo "Total: 52 tests"
}

if $LIST_ONLY; then
  print_test_list
  exit 0
fi

# =============================================================================
# Pre-flight
# =============================================================================
echo -e "${_C}══════════════════════════════════════════════════${_N}"
echo -e "${_C} FEX-Emu Test Suite${_N}"
echo -e "${_C}══════════════════════════════════════════════════${_N}"
echo ""
echo "Mode:       $TEST_MODE"
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
# Phase 1: infra (10 tests) — VM setup verification
# =============================================================================
run_infra() {
  header "Phase 1: Infrastructure (infra)"
  assert_vm_running

  # INF01: OS info
  run_test "INF01" "OS info" "ssh" \
    "cat /etc/os-release | grep PRETTY_NAME"

  # INF02: Page size
  if test_enabled "INF02"; then
    local page_size
    page_size=$(ssh_cmd "getconf PAGESIZE" || echo "ERROR")
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "INF02" "Page size = 4096"
    if [[ "$page_size" = "4096" ]]; then
      _pass "INF02" "Page size = 4096"
    else
      _fail "INF02" "Page size = 4096" "got: $page_size"
    fi
  fi

  # INF03: FEXInterpreter installed
  run_test "INF03" "FEXInterpreter installed" "ssh" \
    "which FEXInterpreter 2>/dev/null && echo FOUND || echo MISSING" "FOUND"

  # INF04: FEX version
  if test_enabled "INF04"; then
    local fex_ver
    fex_ver=$(ssh_cmd "rpm -q --qf '%{VERSION}' fex-emu 2>/dev/null" || echo "")
    if [[ -z "$fex_ver" || "$fex_ver" == *"not installed"* ]]; then
      fex_ver=$(ssh_cmd "grep -ao 'FEX-[0-9][0-9]*' /usr/bin/FEXInterpreter 2>/dev/null | head -1" || echo "")
    fi
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "INF04" "FEX version"
    if [[ -n "$fex_ver" ]]; then
      _pass "INF04" "FEX version" "$fex_ver"
    else
      _skip "INF04" "FEX version" "could not determine"
      TOTAL=$((TOTAL - 1))
    fi
  fi

  # INF05: FEX RootFS
  run_test "INF05" "FEX RootFS found" "ssh" \
    "ls -d /usr/share/fex-emu/RootFS* 2>/dev/null || ls -d /var/lib/fex-emu* 2>/dev/null || echo MISSING" "/"

  # INF06: Virtualization type
  run_test "INF06" "Virtualization type = vm-other" "ssh" \
    "systemd-detect-virt" "vm-other"

  # INF07: binfmt handler registered
  run_test "INF07" "binfmt handler registered" "ssh" \
    "ls /proc/sys/fs/binfmt_misc/ | grep -iE 'fex|x86_64' || echo NONE"

  # INF08: x86_64 handler details
  if test_enabled "INF08"; then
    local handler_info=""
    for h in FEX-x86_64 fex-x86_64 qemu-x86_64; do
      handler_info=$(ssh_cmd "cat /proc/sys/fs/binfmt_misc/$h 2>/dev/null" || echo "")
      [[ -n "$handler_info" ]] && break
    done
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "INF08" "x86_64 handler details"
    if [[ -n "$handler_info" ]]; then
      local interp
      interp=$(echo "$handler_info" | grep '^interpreter' | awk '{print $2}')
      _pass "INF08" "x86_64 handler details" "interpreter=$interp"
    else
      _fail "INF08" "x86_64 handler details" "no x86_64 handler found"
    fi
  fi

  # INF09: x86 (32-bit) handler
  if test_enabled "INF09"; then
    local handler32=""
    for h in FEX-x86 fex-x86 FEX-i386 qemu-i386; do
      handler32=$(ssh_cmd "cat /proc/sys/fs/binfmt_misc/$h 2>/dev/null" || echo "")
      [[ -n "$handler32" ]] && break
    done
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "INF09" "x86 (32-bit) handler"
    if [[ -n "$handler32" ]]; then
      _pass "INF09" "x86 (32-bit) handler" "registered"
    else
      _skip "INF09" "x86 (32-bit) handler" "not registered"
      TOTAL=$((TOTAL - 1))
    fi
  fi

  # INF10: QEMU handler status
  if test_enabled "INF10"; then
    local qemu_status
    qemu_status=$(ssh_cmd "cat /proc/sys/fs/binfmt_misc/qemu-x86_64 2>/dev/null" || echo "NOT_REGISTERED")
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "INF10" "QEMU handler status"
    if [[ "$qemu_status" == "NOT_REGISTERED" ]]; then
      _pass "INF10" "QEMU handler status" "not registered"
    elif echo "$qemu_status" | grep -q "disabled"; then
      _pass "INF10" "QEMU handler status" "disabled"
    else
      _pass "INF10" "QEMU handler status" "active (may conflict with FEX)"
    fi
  fi
}

# =============================================================================
# Phase 2: basic (4 tests) — fundamental emulation
# =============================================================================
run_basic() {
  header "Phase 2: Basic Emulation (basic)"

  # Pre-cache
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
# Phase 3: hook (5 tests) — OCI hook verification
# =============================================================================
run_hook() {
  header "Phase 3: OCI Hook (hook)"

  cache_image "docker.io/library/alpine:latest" "linux/amd64" 2>/dev/null || true
  cache_image "docker.io/library/alpine:latest" "linux/arm64" 2>/dev/null || true

  # H01: FEX bind mounts >= 5
  if test_enabled "H01"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "H01" "FEX bind mounts in amd64 (>=5)"
    local mounts
    mounts=$(timeout "$SSH_TIMEOUT" $PODMAN run --rm --platform linux/amd64 alpine \
      sh -c "grep -cE 'FEX|fex-emu' /proc/mounts 2>/dev/null || echo 0" 2>&1 | tail -1)
    if [[ "$mounts" -ge 5 ]] 2>/dev/null; then
      _pass "H01" "FEX bind mounts" "$mounts mounts"
    else
      _fail "H01" "FEX bind mounts" "expected >=5, got: $mounts"
    fi
  fi

  # H02: All mounts read-only
  if test_enabled "H02"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "H02" "All FEX mounts read-only"
    local rw
    rw=$(timeout "$SSH_TIMEOUT" $PODMAN run --rm --platform linux/amd64 alpine \
      sh -c "grep -E 'FEX|fex-emu' /proc/mounts 2>/dev/null | grep -c ' rw,' || echo 0" 2>&1 | tail -1)
    if [[ "$rw" = "0" ]]; then
      _pass "H02" "All FEX mounts read-only"
    else
      _fail "H02" "FEX mounts read-only" "$rw mounts are rw"
    fi
  fi

  # H03: No FEX in arm64 container
  run_test "H03" "No FEX in arm64 container" "grep" \
    "$PODMAN run --rm --platform linux/arm64 alpine sh -c 'test -f /usr/bin/FEXInterpreter && echo FOUND || echo ABSENT'" "ABSENT"

  # H04: RootFS mount type = erofs
  if test_enabled "H04"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "H04" "FEX RootFS mount type = erofs"
    local fstype
    fstype=$(timeout "$SSH_TIMEOUT" $PODMAN run --rm --platform linux/amd64 alpine \
      sh -c "grep 'fex-emu-rootfs' /proc/mounts 2>/dev/null | awk '{print \$3}'" 2>&1 | tail -1)
    if [[ "$fstype" = "erofs" ]]; then
      _pass "H04" "RootFS mount type = erofs"
    else
      _fail "H04" "RootFS mount type" "expected erofs, got: $fstype"
    fi
  fi

  # H05: Code cache env = 1
  run_test "H05" "Code cache env = 1" "grep" \
    "$PODMAN run --rm --platform linux/amd64 alpine sh -c 'printenv FEX_ENABLECODECACHINGWIP 2>/dev/null'" "1"
}

# =============================================================================
# Phase 4: env (11 tests) — environment variable injection
# =============================================================================
run_env() {
  header "Phase 4: Environment Variables (env)"

  cache_image "$IMG" "linux/amd64" 2>/dev/null || true
  cache_image "$IMG" "linux/arm64" 2>/dev/null || true

  # E01: Code cache enabled + files generated
  if test_enabled "E01"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E01" "Code cache enabled + files generated"
    local out
    out=$($PODMAN run --rm $PLATFORM $IMG sh -c '
      echo CACHE=$FEX_ENABLECODECACHINGWIP
      ls / > /dev/null 2>&1; sleep 2
      CACHE_FILES=$(find /tmp/fex-data/cache/ -type f 2>/dev/null | wc -l)
      echo CACHE_FILES=$CACHE_FILES
    ' 2>&1)
    local cache_val cache_files
    cache_val=$(echo "$out" | grep 'CACHE=' | head -1 | cut -d= -f2)
    cache_files=$(echo "$out" | grep 'CACHE_FILES=' | cut -d= -f2 | tr -d ' ')
    if [[ "$cache_val" = "1" && "${cache_files:-0}" -gt 0 ]]; then
      _pass "E01" "Code cache enabled + files" "env=1, ${cache_files} files"
    else
      _fail "E01" "Code cache enabled + files" "env=$cache_val, files=${cache_files:-0}"
    fi
  fi

  # E02: Code cache disabled
  run_test "E02" "Code cache disabled (env override)" "fn" \
    "$PODMAN run --rm $PLATFORM -e FEX_ENABLECODECACHINGWIP=0 $IMG sh -c 'echo \$FEX_ENABLECODECACHINGWIP'" \
    'grep -q "0"'

  # E03: Verbose cache pipeline (2-run)
  if test_enabled "E03"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E03" "Verbose cache pipeline (2-run)"
    local cnt="e3-verbose-$$"
    $PODMAN rm -f "$cnt" > /dev/null 2>&1 || true
    $PODMAN run --name "$cnt" $PLATFORM \
      -e FEX_VERBOSE_CACHE=1 -e FEX_SILENTLOG=false -e FEX_OUTPUTLOG=stderr \
      $IMG sh -c 'echo hello' > /dev/null 2>&1 || true
    local out2
    out2=$($PODMAN start -a "$cnt" 2>&1) || true
    $PODMAN rm -f "$cnt" > /dev/null 2>&1 || true
    if echo "$out2" | grep -qi "populated cache\|Compiling code"; then
      _pass "E03" "Verbose cache pipeline" "cache pipeline visible"
    else
      _fail "E03" "Verbose cache pipeline" "no cache pipeline output"
    fi
  fi

  # E04: No verbose cache (control)
  if test_enabled "E04"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E04" "No verbose cache (control)"
    local cnt="e4-control-$$"
    $PODMAN rm -f "$cnt" > /dev/null 2>&1 || true
    $PODMAN run --name "$cnt" $PLATFORM \
      -e FEX_SILENTLOG=false -e FEX_OUTPUTLOG=stderr \
      $IMG sh -c 'echo hello' > /dev/null 2>&1 || true
    local out2
    out2=$($PODMAN start -a "$cnt" 2>&1) || true
    $PODMAN rm -f "$cnt" > /dev/null 2>&1 || true
    if echo "$out2" | grep -q "hello" && ! echo "$out2" | grep -qi "populated cache"; then
      _pass "E04" "No verbose cache" "clean, no pipeline detail"
    else
      _fail "E04" "No verbose cache" "unexpected pipeline output"
    fi
  fi

  # E07: FEX log visible
  if test_enabled "E07"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E07" "FEX log visible (SILENTLOG=false)"
    local out
    out=$($PODMAN run --rm $PLATFORM -e FEX_SILENTLOG=false -e FEX_OUTPUTLOG=stderr $IMG uname -m 2>&1)
    if echo "$out" | grep -q "x86_64" && echo "$out" | grep -q "^D "; then
      _pass "E07" "FEX log visible" "debug lines present"
    else
      _fail "E07" "FEX log visible" "no debug output"
    fi
  fi

  # E08: Default log silent
  if test_enabled "E08"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E08" "Default log silent (clean output)"
    local out
    out=$($PODMAN run --rm $PLATFORM $IMG sh -c 'echo hello' 2>&1)
    if echo "$out" | grep -q "hello" && ! echo "$out" | grep -q "^D "; then
      _pass "E08" "Default log silent" "clean output"
    else
      _fail "E08" "Default log silent" "debug lines present"
    fi
  fi

  # E11-E13: OCI hook env vars
  run_test "E11" "OCI hook: FEX_APP_DATA_LOCATION" "fn" \
    "$PODMAN run --rm $PLATFORM $IMG sh -c 'echo \$FEX_APP_DATA_LOCATION'" \
    'grep -q "/tmp/fex-data/"'

  run_test "E12" "OCI hook: FEX_APP_CONFIG_LOCATION" "fn" \
    "$PODMAN run --rm $PLATFORM $IMG sh -c 'echo \$FEX_APP_CONFIG_LOCATION'" \
    'grep -q "/tmp/fex-data/"'

  run_test "E13" "OCI hook: FEX_APP_CACHE_LOCATION" "fn" \
    "$PODMAN run --rm $PLATFORM $IMG sh -c 'echo \$FEX_APP_CACHE_LOCATION'" \
    'grep -q "/tmp/fex-data/cache/"'

  # E14: All env sources combined (hook + containers.conf + user -e)
  if test_enabled "E14"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E14" "All env sources combined"
    local out
    out=$($PODMAN run --rm $PLATFORM -e FEX_USERPARAM=test_value $IMG sh -c 'env | grep FEX | sort' 2>&1)
    local has_hook has_conf has_user
    has_hook=$(echo "$out" | grep -c "FEX_APP_DATA_LOCATION" || true)
    has_conf=$(echo "$out" | grep -c "FEX_ENABLECODECACHINGWIP" || true)
    has_user=$(echo "$out" | grep -c "FEX_USERPARAM=test_value" || true)
    if [[ "$has_hook" -ge 1 && "$has_conf" -ge 1 && "$has_user" -ge 1 ]]; then
      _pass "E14" "All env sources combined" "hook + conf + user-e"
    else
      _fail "E14" "All env sources combined" "hook=$has_hook conf=$has_conf user=$has_user"
    fi
  fi

  # E15: ARM64 no FEX bind mounts
  if test_enabled "E15"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E15" "ARM64: no FEX bind mounts"
    local fex_mounts
    fex_mounts=$($PODMAN run --rm --platform linux/arm64 $IMG sh -c \
      'grep -cE "fex-emu" /proc/mounts 2>/dev/null || echo 0' 2>&1 | tail -1)
    if [[ "${fex_mounts:-0}" = "0" ]]; then
      _pass "E15" "ARM64: no FEX bind mounts" "0 mounts"
    else
      _fail "E15" "ARM64: no FEX bind mounts" "found $fex_mounts FEX mounts"
    fi
  fi
}

# =============================================================================
# Phase 5: issue (17 tests) — GitHub Issue regression
# Execution order: timeout ascending (60s → 90-120s → 300-360s)
#
# run scripts use `pcmd` (exported function) and PODMAN_CONNECTION env.
# build tests use `podman build --platform linux/amd64` on a Dockerfile dir.
# =============================================================================

# Export pcmd for child scripts (fex-emu-tests/run/*.sh depend on it)
pcmd() {
  if [ -n "${PODMAN_CONNECTION:-}" ]; then
    podman --connection "${PODMAN_CONNECTION}" "$@"
  else
    podman "$@"
  fi
}
export -f pcmd

# run_issue_script: wrapper for run/ scripts (sets env, runs via bash)
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

# run_issue_build: wrapper for build/ Dockerfiles (podman build)
run_issue_build() {
  local id="$1" name="$2" build_dir="$3" tout="${4:-120}"
  test_enabled "$id" || return 0
  TOTAL=$((TOTAL + 1))
  printf "%-6s %-45s " "$id" "$name"
  _log "=== $id: $name === (build: $build_dir, timeout=${tout}s)"
  local start_time=$(date +%s) output="" exit_code=0
  output=$(timeout "$tout" $PODMAN build --platform linux/amd64 -t "fex-test-$(echo "$id" | tr '[:upper:]' '[:lower:]')" "$build_dir" 2>&1) && exit_code=0 || exit_code=$?
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
  header "Phase 5: Issue Regression (issue)"

  # --- 60s group (7 tests) ---
  # I07: su -l login shell (#26656)
  run_issue_script "I07" "su -l login shell (#26656)" \
    "${FEX_TESTS_DIR}/run/16-su-login-shell.sh" 60

  # I09: Go godump build (#26919)
  run_issue_build "I09" "Go godump build (#26919)" \
    "${FEX_TESTS_DIR}/build/13-go-build" 60

  # I11: Arch Linux hang (#27210)
  run_issue_script "I11" "Arch Linux hang (#27210)" \
    "${FEX_TESTS_DIR}/run/06-archlinux.sh" 60

  # I13: redis-cluster SIGSEGV (#27601)
  run_issue_script "I13" "redis-cluster SIGSEGV (#27601)" \
    "${FEX_TESTS_DIR}/run/14-redis-cluster.sh" 60

  # I14: Ubuntu hang (#27799)
  run_issue_script "I14" "Ubuntu hang (#27799)" \
    "${FEX_TESTS_DIR}/run/08-ubuntu.sh" 60

  # I15: Fedora hang (#27817)
  run_issue_script "I15" "Fedora hang (#27817)" \
    "${FEX_TESTS_DIR}/run/07-fedora.sh" 60

  # I16: rustc SIGSEGV (#28169)
  run_issue_script "I16" "rustc SIGSEGV (#28169)" \
    "${FEX_TESTS_DIR}/run/03-rustc.sh" 60

  # --- 90-120s group (7 tests) ---
  # I02: SWC/Next.js SIGILL (#23269)
  run_issue_script "I02" "SWC/Next.js SIGILL (#23269)" \
    "${FEX_TESTS_DIR}/run/15-swc-nextjs.sh" 120

  # I03: sudo BuildKit (#24647)
  run_issue_build "I03" "sudo BuildKit (#24647)" \
    "${FEX_TESTS_DIR}/build/11-sudo-buildkit" 120

  # I05: PyArrow SIGSEGV (#26036)
  run_issue_script "I05" "PyArrow SIGSEGV (#26036)" \
    "${FEX_TESTS_DIR}/run/04-pyarrow.sh" 90

  # I06: Express freeze (#26572)
  run_issue_script "I06" "Express freeze (#26572)" \
    "${FEX_TESTS_DIR}/run/12-nodejs-express.sh" 120

  # I08: Go hello build (#26881)
  run_issue_build "I08" "Go hello build (#26881)" \
    "${FEX_TESTS_DIR}/build/09-go-hello" 120

  # I10: MSSQL 2022 SIGSEGV (#27078)
  run_issue_script "I10" "MSSQL 2022 SIGSEGV (#27078)" \
    "${FEX_TESTS_DIR}/run/02-mssql-2022.sh" 120

  # I17: MSSQL 2025 AVX (#28184)
  run_issue_script "I17" "MSSQL 2025 AVX (#28184)" \
    "${FEX_TESTS_DIR}/run/01-mssql-2025.sh" 120

  # --- 300-360s group (3 tests, --full only) ---
  # I01: gawk SIGSEGV (#23219)
  run_issue_script "I01" "gawk SIGSEGV (#23219)" \
    "${FEX_TESTS_DIR}/run/13b-gawk.sh" 360

  # I04: Angular/Node build (#25272)
  run_issue_build "I04" "Angular/Node build (#25272)" \
    "${FEX_TESTS_DIR}/build/10-angular" 300

  # I12: jemalloc SIGSEGV (#27320)
  run_issue_script "I12" "jemalloc SIGSEGV (#27320)" \
    "${FEX_TESTS_DIR}/run/05-jemalloc.sh" 360
}

# =============================================================================
# Phase 6: workload (2 tests)
# =============================================================================
run_workload() {
  header "Phase 6: Workload (workload)"

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
# Phase 7: stress (3 tests)
# =============================================================================
run_stress() {
  header "Phase 7: Stress Tests (stress)"
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
category_enabled "hook"     && run_hook
category_enabled "env"      && run_env
category_enabled "issue"    && run_issue
category_enabled "workload" && run_workload
category_enabled "stress"   && run_stress

print_summary
exit $?
