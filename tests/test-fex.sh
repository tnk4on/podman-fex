#!/usr/bin/env bash
# test-fex.sh — FEX-Emu unified test runner
# 7 categories, 61 tests (infra/basic/hook/env/issue/workload/stress)
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
PLATFORM="--pull=never --platform linux/amd64"
ARM_PLATFORM="--pull=never --platform linux/arm64"
AMD64_IMG="localhost/fex-test-alpine-amd64:latest"
ARM64_IMG="localhost/fex-test-alpine-arm64:latest"
IMG="$AMD64_IMG"
FEX_TESTS_DIR="${SCRIPT_DIR}"

# Setup signal traps for graceful interruption
setup_traps

# Known upstream FEX-Emu failures (xfail — expected to fail)
# These are tracked FEX-Emu issues, not regressions in our code.
# Format: space-separated test IDs
KNOWN_FAIL="I04 I08 I09 I10 I17"

# Check if a test ID is in the known-fail list
is_known_fail() {
  [[ " $KNOWN_FAIL " == *" $1 "* ]]
}

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
infra     INF11  Podman version (VM)                          
infra     INF12  FEXServer version                            
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
env       E16    VM containers.conf: all FEX env (rootless)  
env       E17    VM containers.conf: all FEX env (rootful)   
env       E18    VM Config.json: EnableCodeCachingWIP=true   
env       E19    No legacy drop-in exists                    
env       E20    Cache dir structure in container             
env       E21    Warm cache has more files than cold          
env       E22    FEXServer spawns inside x86_64 container    
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
  echo "Total: 61 tests"
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

assert_vm_running

# =============================================================================
# Pre-cache — load all required images before any test phase
# Prevents --platform from triggering slow/hanging registry pulls.
# =============================================================================
find_cached_image_id() {
  local image_ref="$1"
  local platform="$2"
  local wanted_arch="${platform#*/}"
  local image_ids
  image_ids=$($PODMAN images --filter "reference=${image_ref}" --format '{{.ID}}' --no-trunc 2>/dev/null || true)
  for image_id in $image_ids; do
    local image_arch
    image_arch=$($PODMAN inspect "$image_id" --format '{{.Architecture}}' 2>/dev/null || true)
    if [[ "$image_arch" == "$wanted_arch" ]]; then
      echo "$image_id"
      return 0
    fi
  done
  return 1
}

tag_cached_image() {
  local image_ref="$1"
  local platform="$2"
  local local_tag="$3"
  local image_id
  image_id=$(find_cached_image_id "$image_ref" "$platform") || return 1
  $PODMAN tag "$image_id" "$local_tag" >/dev/null 2>&1
}

pre_cache_images() {
  header "Pre-cache: loading images from local archive"
  local imgs=(
    "docker.io/library/alpine:latest|linux/amd64|$AMD64_IMG"
    "docker.io/library/alpine:latest|linux/arm64|$ARM64_IMG"
    "docker.io/library/alpine:latest|linux/amd64|alpine:latest"
    "docker.io/library/fedora:latest|linux/amd64|"
    "docker.io/library/ubuntu:latest|linux/amd64|"
    "docker.io/library/ubuntu:25.10|linux/amd64|"
    "docker.io/library/debian:bookworm-slim|linux/amd64|"
    "docker.io/library/python:3.11-slim|linux/amd64|"
    "docker.io/library/node:lts-slim|linux/amd64|"
    "docker.io/library/node:lts-slim|linux/amd64|node:lts-slim"
    "docker.io/library/node:20-alpine3.18|linux/amd64|"
    "docker.io/library/node:20-alpine3.18|linux/amd64|node:20-alpine3.18"
    "docker.io/library/golang:1.24-alpine|linux/amd64|"
    "docker.io/library/golang:1.24-alpine|linux/amd64|golang:1.24-alpine"
    "docker.io/library/rust:1.93.0-bookworm|linux/amd64|"
    "docker.io/library/archlinux:latest|linux/amd64|"
    "docker.io/duyquyen/redis-cluster|linux/amd64|"
    "registry.access.redhat.com/ubi10/ubi-micro:latest|linux/amd64|"
    "registry.access.redhat.com/ubi8:latest|linux/amd64|"
    "mcr.microsoft.com/mssql/server:2022-latest|linux/amd64|"
    "mcr.microsoft.com/mssql/server:2025-latest|linux/amd64|"
  )
  local loaded=0 failed=0
  for entry in "${imgs[@]}"; do
    local img plat local_tag
    IFS='|' read -r img plat local_tag <<< "$entry"
    if cache_image "$img" "$plat"; then
      if [[ -n "$local_tag" ]] && ! tag_cached_image "$img" "$plat" "$local_tag"; then
        echo "  WARN: failed to tag $img ($plat) as $local_tag"
        failed=$((failed + 1))
      else
        loaded=$((loaded + 1))
      fi
    else
      echo "  WARN: failed to cache $img ($plat)"
      failed=$((failed + 1))
    fi
  done
  echo "  Pre-cache: ${loaded} loaded, ${failed} failed"
  if [[ $failed -gt 0 ]]; then
    echo "ERROR: pre-cache failed; aborting to avoid registry-dependent hangs"
    return 1
  fi
  echo ""
}
pre_cache_images || exit 1

# =============================================================================
# Phase 1: infra (12 tests) — VM setup verification
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
  # Priority: binary version (OVERRIDE_VERSION) > RPM version
  if test_enabled "INF04"; then
    local fex_ver
    # Try binary version first (embedded via -DOVERRIDE_VERSION)
    fex_ver=$(ssh_cmd "grep -aoPm1 'FEX-[0-9][0-9]*' /usr/bin/FEXInterpreter 2>/dev/null" || echo "")
    if [[ -z "$fex_ver" ]]; then
      # Fallback: FEXServer stores "FEX-Emu (VERSION)" format
      fex_ver=$(ssh_cmd "grep -aoP '(?<=FEX-Emu \\()[^)]+' /usr/bin/FEXServer 2>/dev/null | head -1" || echo "")
    fi
    if [[ -z "$fex_ver" ]]; then
      # Fallback: RPM version
      fex_ver=$(ssh_cmd "rpm -q --qf '%{VERSION}' fex-emu 2>/dev/null" || echo "")
      [[ "$fex_ver" == *"not installed"* ]] && fex_ver=""
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

  # INF11: Podman version (VM)
  if test_enabled "INF11"; then
    local podman_ver
    podman_ver=$(ssh_cmd "podman --version 2>/dev/null" || echo "")
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "INF11" "Podman version (VM)"
    if [[ -n "$podman_ver" ]]; then
      _pass "INF11" "Podman version (VM)" "$podman_ver"
    else
      _fail "INF11" "Podman version (VM)" "not found"
    fi
  fi

  # INF12: FEXServer version
  if test_enabled "INF12"; then
    local fexserver_ver
    # Try binary embedded version (OVERRIDE_VERSION)
    fexserver_ver=$(ssh_cmd "grep -aoPm1 'FEX-[0-9][0-9]*' /usr/bin/FEXServer 2>/dev/null" || echo "")
    if [[ -z "$fexserver_ver" ]]; then
      # Fallback: FEX-Emu (VERSION) format
      fexserver_ver=$(ssh_cmd "grep -aoP '(?<=FEX-Emu \\()[^)]+' /usr/bin/FEXServer 2>/dev/null | head -1" || echo "")
    fi
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "INF12" "FEXServer version"
    if [[ -n "$fexserver_ver" ]]; then
      _pass "INF12" "FEXServer version" "$fexserver_ver"
    else
      _skip "INF12" "FEXServer version" "could not determine"
      TOTAL=$((TOTAL - 1))
    fi
  fi
}

# =============================================================================
# Phase 2: basic (4 tests) — fundamental emulation
# =============================================================================
run_basic() {
  header "Phase 2: Basic Emulation (basic)"

  # B01: x86_64 container
  run_test "B01" "x86_64 container (alpine)" "grep" \
    "$PODMAN run --rm $PLATFORM $IMG uname -m" "x86_64"

  # B02: ARM64 regression
  run_test "B02" "ARM64 regression" "grep" \
    "$PODMAN run --rm $ARM_PLATFORM $ARM64_IMG uname -m" "aarch64"

  # B03: Stability (5x sequential)
  if test_enabled "B03"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "B03" "Stability (5x sequential)"
    local ok=true
    for i in 1 2 3 4 5; do
      local r
      r=$($PODMAN run --rm $PLATFORM $IMG uname -m 2>/dev/null) || true
      [[ "$r" != "x86_64" ]] && { ok=false; break; }
    done
    if $ok; then _pass "B03" "Stability (5x sequential)" "5/5"
    else _fail "B03" "Stability (5x sequential)"; fi
  fi

  # B04: Multi-distro
  if test_enabled "B04"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "B04" "Multi-distro (fedora/ubuntu/ubi)"
    local ok=true fail_img=""
    for img in docker.io/library/fedora:latest docker.io/library/ubuntu:latest registry.access.redhat.com/ubi10/ubi-micro:latest; do
      local r
      r=$($PODMAN run --rm $PLATFORM "$img" uname -m 2>/dev/null) || true
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

  # H01: FEX bind mounts >= 5
  if test_enabled "H01"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "H01" "FEX bind mounts in amd64 (>=5)"
    local mounts
    mounts=$(timeout "$SSH_TIMEOUT" $PODMAN run --rm $PLATFORM $IMG \
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
    rw=$(timeout "$SSH_TIMEOUT" $PODMAN run --rm $PLATFORM $IMG \
      sh -c "grep -E 'FEX|fex-emu' /proc/mounts 2>/dev/null | grep -c ' rw,' || echo 0" 2>&1 | tail -1)
    if [[ "$rw" = "0" ]]; then
      _pass "H02" "All FEX mounts read-only"
    else
      _fail "H02" "FEX mounts read-only" "$rw mounts are rw"
    fi
  fi

  # H03: No FEX in arm64 container
  run_test "H03" "No FEX in arm64 container" "grep" \
    "$PODMAN run --rm $ARM_PLATFORM $ARM64_IMG sh -c 'test -f /usr/bin/FEXInterpreter && echo FOUND || echo ABSENT'" "ABSENT"

  # H04: RootFS mount type = erofs
  if test_enabled "H04"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "H04" "FEX RootFS mount type = erofs"
    local fstype
    fstype=$(timeout "$SSH_TIMEOUT" $PODMAN run --rm $PLATFORM $IMG \
      sh -c "grep 'fex-emu-rootfs' /proc/mounts 2>/dev/null | awk '{print \$3}'" 2>&1 | tail -1)
    if [[ "$fstype" = "erofs" ]]; then
      _pass "H04" "RootFS mount type = erofs"
    else
      _fail "H04" "RootFS mount type" "expected erofs, got: $fstype"
    fi
  fi

  # H05: Code cache env = 1
  run_test "H05" "Code cache env = 1" "grep" \
    "$PODMAN run --rm $PLATFORM $IMG sh -c 'printenv FEX_ENABLECODECACHINGWIP 2>/dev/null'" "1"
}

# =============================================================================
# Phase 4: env (11 tests) — environment variable injection
# =============================================================================
run_env() {
  header "Phase 4: Environment Variables (env)"

  # E01: Code cache enabled + files generated
  if test_enabled "E01"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E01" "Code cache enabled + files generated"
    local out
    out=$($PODMAN run --rm $PLATFORM $IMG sh -c '
      echo CACHE=$FEX_ENABLECODECACHINGWIP
      ls / > /dev/null 2>&1; sleep 2
      CACHE_FILES=$(find /tmp/fex-emu/cache/ -type f 2>/dev/null | wc -l)
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
    'grep -q "/tmp/fex-emu/"'

  run_test "E12" "OCI hook: FEX_APP_CONFIG_LOCATION" "fn" \
    "$PODMAN run --rm $PLATFORM $IMG sh -c 'echo \$FEX_APP_CONFIG_LOCATION'" \
    'grep -q "/tmp/fex-emu/"'

  run_test "E13" "OCI hook: FEX_APP_CACHE_LOCATION" "fn" \
    "$PODMAN run --rm $PLATFORM $IMG sh -c 'echo \$FEX_APP_CACHE_LOCATION'" \
    'grep -q "/tmp/fex-emu/cache/"'

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
    fex_mounts=$($PODMAN run --rm $ARM_PLATFORM $ARM64_IMG sh -c \
      'grep -cE "fex-emu" /proc/mounts 2>/dev/null || echo 0' 2>&1 | tail -1)
    if [[ "${fex_mounts:-0}" = "0" ]]; then
      _pass "E15" "ARM64: no FEX bind mounts" "0 mounts"
    else
      _fail "E15" "ARM64: no FEX bind mounts" "found $fex_mounts FEX mounts"
    fi
  fi

  # E16: VM containers.conf has all 4 required FEX env vars (rootless)
  if test_enabled "E16"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E16" "VM containers.conf: all FEX env (rootless)"
    local conf
    conf=$(ssh_cmd "cat ~/.config/containers/containers.conf 2>/dev/null" 2>&1)
    local missing=""
    for var in FEX_APP_DATA_LOCATION FEX_APP_CONFIG_LOCATION FEX_APP_CACHE_LOCATION FEX_ENABLECODECACHINGWIP; do
      echo "$conf" | grep -q "$var" || missing="$missing $var"
    done
    if [[ -z "$missing" ]]; then
      _pass "E16" "VM containers.conf: all FEX env (rootless)" "4/4 vars present"
    else
      _fail "E16" "VM containers.conf: all FEX env (rootless)" "missing:$missing"
    fi
  fi

  # E17: VM containers.conf has all 4 required FEX env vars (rootful)
  if test_enabled "E17"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E17" "VM containers.conf: all FEX env (rootful)"
    local conf
    conf=$(ssh_cmd "sudo cat /root/.config/containers/containers.conf 2>/dev/null" 2>&1)
    local missing=""
    for var in FEX_APP_DATA_LOCATION FEX_APP_CONFIG_LOCATION FEX_APP_CACHE_LOCATION FEX_ENABLECODECACHINGWIP; do
      echo "$conf" | grep -q "$var" || missing="$missing $var"
    done
    if [[ -z "$missing" ]]; then
      _pass "E17" "VM containers.conf: all FEX env (rootful)" "4/4 vars present"
    else
      _fail "E17" "VM containers.conf: all FEX env (rootful)" "missing:$missing"
    fi
  fi

  # E18: Config.json has EnableCodeCachingWIP: true
  if test_enabled "E18"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E18" "VM Config.json: EnableCodeCachingWIP=true"
    local cjson
    cjson=$(ssh_cmd "cat /etc/fex-emu/Config.json 2>/dev/null" 2>&1)
    if echo "$cjson" | grep -q '"EnableCodeCachingWIP".*true'; then
      _pass "E18" "VM Config.json: EnableCodeCachingWIP=true"
    else
      _fail "E18" "VM Config.json: EnableCodeCachingWIP=true" "not found or false"
    fi
  fi

  # E19: No legacy drop-in exists (containers.conf.d/fex-code-cache.conf)
  if test_enabled "E19"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E19" "No legacy drop-in exists"
    local dropin_rootless dropin_rootful
    dropin_rootless=$(ssh_cmd "test -f ~/.config/containers/containers.conf.d/fex-code-cache.conf && echo EXISTS || echo NONE" 2>&1 | tail -1)
    dropin_rootful=$(ssh_cmd "sudo test -f /root/.config/containers/containers.conf.d/fex-code-cache.conf && echo EXISTS || echo NONE" 2>&1 | tail -1)
    if [[ "$dropin_rootless" = "NONE" && "$dropin_rootful" = "NONE" ]]; then
      _pass "E19" "No legacy drop-in exists" "clean"
    else
      _fail "E19" "No legacy drop-in exists" "rootless=$dropin_rootless rootful=$dropin_rootful"
    fi
  fi

  # E20: Cache directory structure created inside container
  if test_enabled "E20"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E20" "Cache dir structure in container"
    local out
    out=$($PODMAN run --rm $PLATFORM $IMG sh -c '
      ls / > /dev/null 2>&1; sleep 1
      for d in /tmp/fex-emu /tmp/fex-emu/cache /tmp/fex-emu/cache/codemap; do
        test -d "$d" && echo "OK:$d" || echo "MISSING:$d"
      done
    ' 2>&1)
    local missing
    missing=$(echo "$out" | grep -c "MISSING:" || true)
    if [[ "$missing" -eq 0 ]]; then
      _pass "E20" "Cache dir structure in container" "3/3 dirs"
    else
      _fail "E20" "Cache dir structure in container" "$(echo "$out" | grep MISSING | tr '\n' ' ')"
    fi
  fi

  # E21: Warm cache has more files than cold (second run reuses/grows cache)
  if test_enabled "E21"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E21" "Warm cache has more files than cold"
    local cnt="e21-cache-$$"
    $PODMAN rm -f "$cnt" > /dev/null 2>&1 || true
    # Cold run
    $PODMAN run --name "$cnt" $PLATFORM $IMG sh -c '
      ls / > /dev/null 2>&1; sleep 2
      find /tmp/fex-emu/cache/ -type f 2>/dev/null | wc -l
    ' > /dev/null 2>&1 || true
    # Warm run (same container = same cache)
    local warm_out
    warm_out=$($PODMAN start -a "$cnt" 2>&1)
    local warm_files
    warm_files=$(echo "$warm_out" | grep -E '^[0-9]+$' | tail -1)
    $PODMAN rm -f "$cnt" > /dev/null 2>&1 || true
    if [[ "${warm_files:-0}" -gt 0 ]]; then
      _pass "E21" "Warm cache has more files than cold" "${warm_files} files"
    else
      _fail "E21" "Warm cache has more files than cold" "warm=${warm_files:-0}"
    fi
  fi

  # E22: FEXServer process spawns inside x86_64 container
  if test_enabled "E22"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "E22" "FEXServer spawns inside x86_64 container"
    local out
    out=$($PODMAN run --rm $PLATFORM $IMG sh -c '
      ls / > /dev/null 2>&1; sleep 1
      ps aux 2>/dev/null | grep -c "[F]EXServer" || echo 0
    ' 2>&1)
    local server_count
    server_count=$(echo "$out" | grep -E '^[0-9]+$' | tail -1)
    if [[ "${server_count:-0}" -ge 1 ]]; then
      _pass "E22" "FEXServer spawns inside x86_64 container" "${server_count} process(es)"
    else
      _fail "E22" "FEXServer spawns inside x86_64 container" "count=${server_count:-0}"
    fi
  fi
}

# =============================================================================
# Phase 5: issue (17 tests) — GitHub Issue regression
# Execution order: issue number ascending (I01 → I17)
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
  elif is_known_fail "$id"; then
    _xfail "$id" "$name" "upstream FEX issue (exit $exit_code, ${duration}s)"
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
  output=$(timeout "$tout" $PODMAN build --pull-never --platform linux/amd64 -t "fex-test-$(echo "$id" | tr '[:upper:]' '[:lower:]')" "$build_dir" 2>&1) && exit_code=0 || exit_code=$?
  local duration=$(( $(date +%s) - start_time ))
  _log "$output"
  _log "exit_code=$exit_code duration=${duration}s"
  _log ""
  if [[ $exit_code -eq 0 ]]; then
    _pass "$id" "$name" "${duration}s"
  elif is_known_fail "$id"; then
    _xfail "$id" "$name" "upstream FEX issue (exit $exit_code, ${duration}s)"
  elif [[ $exit_code -eq 124 ]]; then
    echo -e "${_Y}\u23f1\ufe0f TIMEOUT${_N} (${duration}s)"
    _log "  \u23f1\ufe0f TIMEOUT $id $name (${duration}s)"
    RESULTS+=("$id|$name|TIMEOUT|${duration}s")
    FAIL=$((FAIL + 1))
  else
    _fail "$id" "$name" "exit $exit_code (${duration}s)"
  fi
}

run_issue() {
  header "Phase 5: Issue Regression (issue)"

  # I01: gawk SIGSEGV (#23219)
  run_issue_script "I01" "gawk SIGSEGV (#23219)" \
    "${FEX_TESTS_DIR}/run/13b-gawk.sh" 360

  # I02: SWC/Next.js SIGILL (#23269)
  run_issue_script "I02" "SWC/Next.js SIGILL (#23269)" \
    "${FEX_TESTS_DIR}/run/15-swc-nextjs.sh" 120

  # I03: sudo BuildKit (#24647)
  run_issue_build "I03" "sudo BuildKit (#24647)" \
    "${FEX_TESTS_DIR}/build/11-sudo-buildkit" 120

  # I04: Angular/Node build (#25272)
  run_issue_build "I04" "Angular/Node build (#25272)" \
    "${FEX_TESTS_DIR}/build/10-angular" 300

  # I05: PyArrow SIGSEGV (#26036)
  run_issue_script "I05" "PyArrow SIGSEGV (#26036)" \
    "${FEX_TESTS_DIR}/run/04-pyarrow.sh" 90

  # I06: Express freeze (#26572)
  run_issue_script "I06" "Express freeze (#26572)" \
    "${FEX_TESTS_DIR}/run/12-nodejs-express.sh" 120

  # I07: su -l login shell (#26656)
  run_issue_script "I07" "su -l login shell (#26656)" \
    "${FEX_TESTS_DIR}/run/16-su-login-shell.sh" 60

  # I08: Go hello build (#26881)
  run_issue_build "I08" "Go hello build (#26881)" \
    "${FEX_TESTS_DIR}/build/09-go-hello" 120

  # I09: Go godump build (#26919)
  run_issue_build "I09" "Go godump build (#26919)" \
    "${FEX_TESTS_DIR}/build/13-go-build" 60

  # I10: MSSQL 2022 SIGSEGV (#27078)
  run_issue_script "I10" "MSSQL 2022 SIGSEGV (#27078)" \
    "${FEX_TESTS_DIR}/run/02-mssql-2022.sh" 120

  # I11: Arch Linux hang (#27210)
  run_issue_script "I11" "Arch Linux hang (#27210)" \
    "${FEX_TESTS_DIR}/run/06-archlinux.sh" 60

  # I12: jemalloc SIGSEGV (#27320)
  run_issue_script "I12" "jemalloc SIGSEGV (#27320)" \
    "${FEX_TESTS_DIR}/run/05-jemalloc.sh" 360

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

  # I17: MSSQL 2025 AVX (#28184)
  run_issue_script "I17" "MSSQL 2025 AVX (#28184)" \
    "${FEX_TESTS_DIR}/run/01-mssql-2025.sh" 120
}

# =============================================================================
# Phase 6: workload (2 tests)
# =============================================================================
run_workload() {
  header "Phase 6: Workload (workload)"

  # W01: dnf install git
  run_test "W01" "dnf install git" "exit" \
    "$PODMAN run --rm $PLATFORM docker.io/library/fedora:latest dnf install -y git"

  # W02: podman build x86_64
  if test_enabled "W02"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "W02" "podman build x86_64"
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/Containerfile" << 'CEOF'
FROM --platform=linux/amd64 docker.io/library/alpine:latest
RUN apk add --no-cache curl && curl --version
CEOF
    perl -0pi -e 's|docker\.io/library/alpine:latest|localhost/fex-test-alpine-amd64:latest|g' "$tmpdir/Containerfile"
    if $PODMAN build --pull-never --platform linux/amd64 -f "$tmpdir/Containerfile" "$tmpdir" > /dev/null 2>&1; then
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

  # S01: 5 sequential x86_64 containers
  if test_enabled "S01"; then
    TOTAL=$((TOTAL + 1))
    printf "%-6s %-45s " "S01" "5 sequential x86_64 containers"
    local ok=0
    for i in $(seq 1 5); do
      local r
      r=$(timeout "$SSH_TIMEOUT" $PODMAN run --rm $PLATFORM $IMG \
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
    r=$(timeout 60 $PODMAN run --rm $PLATFORM $IMG \
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
    arm=$(timeout "$SSH_TIMEOUT" $PODMAN run --rm $ARM_PLATFORM $ARM64_IMG uname -m 2>/dev/null || echo "ERROR")
    x86=$(timeout "$SSH_TIMEOUT" $PODMAN run --rm $PLATFORM $IMG uname -m 2>/dev/null || echo "ERROR")
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
