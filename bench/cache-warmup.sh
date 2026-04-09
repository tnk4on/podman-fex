#!/bin/bash
# FEX-Emu Code Cache Warmup Benchmark
# Measures performance changes across 5 iterations inside the same container
# as FEX code cache accumulates JIT-compiled code.
#
# Usage:
#   ./run-cache-warmup-bench.sh [--connection <name>]
#
# Default: --connection podman-machine-default (rootless)

set -uo pipefail

# Parse arguments
PODMAN_CONNECTION="podman-machine-default"
CACHE_DIR=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --connection) PODMAN_CONNECTION="$2"; shift 2 ;;
    --cache-dir) CACHE_DIR="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CACHE_HELPER="${WORKSPACE_DIR}/scripts/podman-cache-image.sh"
CACHE_DIR="${CACHE_DIR:-${WORKSPACE_DIR}/image-cache}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_DIR="${SCRIPT_DIR}/results/cache_warmup_${TIMESTAMP}"
mkdir -p "${RUN_DIR}"

ITERATIONS=5

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

pcmd() {
  podman --connection "${PODMAN_CONNECTION}" "$@"
}

cache_image() {
  local image="$1"
  if [ ! -x "${CACHE_HELPER}" ]; then
    echo "ERROR: cache helper not found: ${CACHE_HELPER}"
    return 1
  fi
  "${CACHE_HELPER}" --quiet --connection "${PODMAN_CONNECTION}" --platform linux/amd64 --cache-dir "${CACHE_DIR}" "${image}"
}

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   FEX-Emu Code Cache Warmup Benchmark                       ║"
echo "║   ${TIMESTAMP}  Connection: ${PODMAN_CONNECTION}"
echo "║   Iterations per test: ${ITERATIONS}"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "Results directory: ${RUN_DIR}"
echo ""

echo -e "${YELLOW}▶ Pre-cache docker.io images${NC}"
for img in \
  "docker.io/library/fedora:latest" \
  "docker.io/library/archlinux:latest" \
  "docker.io/library/perl:5-slim" \
  "docker.io/library/ubuntu:latest" \
  "docker.io/library/python:3-slim" \
  "docker.io/library/rust:latest"; do
  echo "  - ${img}"
  cache_image "${img}" || exit 1
done
echo ""

# Summary file
SUMMARY="${RUN_DIR}/summary.md"
cat > "${SUMMARY}" <<EOF
# FEX-Emu Code Cache Warmup Benchmark

- **Date**: $(date)
- **Connection**: ${PODMAN_CONNECTION}
- **Iterations**: ${ITERATIONS} per test
- **Mode**: In-container (same container, cache accumulates across iterations)

EOF

# ─────────────────────────────────────────────
# Test runner: run command N times inside one container, timing each
# ─────────────────────────────────────────────
run_cache_test() {
  local test_id="$1"
  local test_name="$2"
  local image="$3"
  local setup_cmd="$4"    # one-time setup (empty string if none)
  local bench_cmd="$5"    # command to repeat and time
  local timeout="${6:-300}"

  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}[${test_id}] ${test_name}${NC}"
  echo -e "${CYAN}  Image: ${image}${NC}"
  echo -e "${CYAN}  Bench: ${bench_cmd}${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  local log_file="${RUN_DIR}/${test_id}-${test_name// /-}.log"
  local cn="fex-cache-${test_id}-$$"

  # Build the in-container script that runs bench_cmd N times with timing
  local inner_script=""

  # Setup phase (if any)
  if [ -n "${setup_cmd}" ]; then
    inner_script+="echo '=== SETUP ===' && ${setup_cmd} && "
  fi

  # Benchmark loop
  inner_script+="for i in \$(seq 1 ${ITERATIONS}); do "
  inner_script+="  echo \"--- Run \$i/${ITERATIONS} ---\"; "
  inner_script+="  START=\$(date +%s%N); "
  inner_script+="  ${bench_cmd}; "
  inner_script+="  RC=\$?; "
  inner_script+="  END=\$(date +%s%N); "
  inner_script+="  ELAPSED=\$(( (END - START) / 1000000 )); "
  inner_script+="  echo \"TIMING: run=\$i elapsed_ms=\${ELAPSED} exit=\${RC}\"; "
  inner_script+="done; "
  inner_script+="echo '=== COMPLETE ==='"

  # Run with timeout (use bash -c to keep shell context for podman path)
  local overall_start=$(date +%s)
  timeout "${timeout}" podman --connection "${PODMAN_CONNECTION}" run --rm --name "${cn}" \
    --arch amd64 "${image}" \
    bash -c "${inner_script}" 2>&1 | tee "${log_file}"
  local overall_exit=${PIPESTATUS[0]}
  local overall_end=$(date +%s)
  local overall_duration=$((overall_end - overall_start))

  # Extract timing lines (macOS compatible — no grep -P)
  local times=()
  local exits=()
  while IFS= read -r line; do
    local ms=$(echo "$line" | sed -n 's/.*elapsed_ms=\([0-9]*\).*/\1/p')
    local rc=$(echo "$line" | sed -n 's/.*exit=\([0-9]*\).*/\1/p')
    if [ -n "$ms" ]; then
      times+=("$ms")
      exits+=("$rc")
    fi
  done < <(grep "^TIMING:" "${log_file}")

  echo ""
  if [ ${#times[@]} -eq 0 ]; then
    echo -e "${RED}  ❌ No timing data collected (exit=${overall_exit}, ${overall_duration}s total)${NC}"
    echo "### ${test_id}: ${test_name}" >> "${SUMMARY}"
    echo "" >> "${SUMMARY}"
    echo "❌ Failed — no timing data (exit=${overall_exit}, ${overall_duration}s)" >> "${SUMMARY}"
    echo "" >> "${SUMMARY}"
    return
  fi

  # Print results
  echo -e "${GREEN}  Results:${NC}"
  for idx in "${!times[@]}"; do
    local run_num=$((idx + 1))
    local secs=$(echo "scale=1; ${times[$idx]} / 1000" | bc)
    echo -e "    Run ${run_num}: ${secs}s (exit=${exits[$idx]})"
  done

  # Calculate speedup: R1 / min of last 3 runs
  if [ ${#times[@]} -ge 3 ]; then
    local first=${times[0]}
    local n=${#times[@]}
    local tail_min=${times[$((n-1))]}
    for ti in $((n-2)) $((n-3)); do
      [ $ti -ge 0 ] && [ "${times[$ti]}" -lt "$tail_min" ] && tail_min=${times[$ti]}
    done
    if [ "$tail_min" -gt 0 ]; then
      local speedup=$(echo "scale=1; $first / $tail_min" | bc)
      echo -e "    ${YELLOW}Speedup (R1 / min R$((n-2))-R${n}): ${speedup}x${NC}"
    fi
  fi

  echo ""

  # Append to summary
  cat >> "${SUMMARY}" <<SECEOF
### ${test_id}: ${test_name}

- **Image**: \`${image}\`
- **Command**: \`${bench_cmd}\`
- **Total**: ${overall_duration}s | Exit: ${overall_exit}

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
SECEOF

  for idx in "${!times[@]}"; do
    local run_num=$((idx + 1))
    local secs=$(echo "scale=1; ${times[$idx]} / 1000" | bc)
    local pct=""
    if [ $idx -gt 0 ] && [ "${times[0]}" -gt 0 ]; then
      pct=$(echo "scale=0; ${times[$idx]} * 100 / ${times[0]}" | bc)
      pct="${pct}%"
    else
      pct="baseline"
    fi
    echo "| ${run_num} | ${secs}s | ${exits[$idx]} | ${pct} |" >> "${SUMMARY}"
  done
  echo "" >> "${SUMMARY}"
}

# ─────────────────────────────────────────────
# Test Suite — selected by observed cache speedup from past logs
#
# | ID | Workload              | Image          | Observed Speedup |
# |----|-----------------------|----------------|-----------------|
# | W1 | dnf check-update      | fedora         | ~15x            |
# | W2 | pacman -Sy            | archlinux      | ~12x            |
# | W3 | perl -e print         | perl:5-slim    | ~8x             |
# | W4 | dpkg -l | wc -l       | ubuntu         | ~7x             |
# | W5 | python3 -c print(42)  | python:3-slim  | ~6x             |
# | W6 | rustc -vV             | rust           | ~4x             |
# | W7 | rpm -V bash           | fedora         | ~3.7x           |
# ─────────────────────────────────────────────

echo -e "\n${YELLOW}▶ In-Container Cache Warmup Tests (${ITERATIONS} iterations each)${NC}\n"

# W1: Fedora dnf check-update (~15x)
run_cache_test "W1" "Fedora dnf check-update" \
  "docker.io/library/fedora:latest" \
  "" \
  "dnf check-update -q 2>/dev/null; true" \
  600

# W2: Arch Linux pacman sync (~12x)
run_cache_test "W2" "Arch pacman sync" \
  "docker.io/library/archlinux:latest" \
  "" \
  "pacman -Sy --noconfirm >/dev/null 2>&1 && echo 'pacman sync done'" \
  600

# W3: Perl interpreter startup (~8x)
run_cache_test "W3" "Perl startup" \
  "docker.io/library/perl:5-slim" \
  "" \
  "perl -e 'print \"hello\\n\"'" \
  120

# W4: Ubuntu dpkg list (~7x)
run_cache_test "W4" "Ubuntu dpkg list" \
  "docker.io/library/ubuntu:latest" \
  "" \
  "dpkg -l | wc -l" \
  120

# W5: Python interpreter startup (~6x)
run_cache_test "W5" "Python startup" \
  "docker.io/library/python:3-slim" \
  "" \
  "python3 -c 'print(42)'" \
  120

# W6: rustc version check (~4x)
run_cache_test "W6" "rustc version" \
  "docker.io/library/rust:latest" \
  "" \
  "rustc -vV" \
  300

# W7: Fedora rpm verify (~3.7x)
run_cache_test "W7" "Fedora rpm verify" \
  "docker.io/library/fedora:latest" \
  "" \
  "rpm -V bash" \
  120

# ─────────────────────────────────────────────
# Final summary
# ─────────────────────────────────────────────

echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║   BENCHMARK COMPLETE                   ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"
echo "Results saved to: ${RUN_DIR}/"
echo ""
echo "--- Summary ---"
cat "${SUMMARY}"
