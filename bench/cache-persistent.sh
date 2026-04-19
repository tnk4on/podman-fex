#!/bin/bash
# FEX-Emu Persistent Container Cache Test
# Tests code cache behavior in persistent containers (no --rm).
# Container stays alive; all rounds run inside a single exec call
# with the same internal loop as warmup bench, ensuring identical
# measurement methodology.
#
# Usage:
#   ./cache-persistent.sh [--connection <name>] [--rounds N]

set -uo pipefail

PODMAN_CONNECTION="podman-machine-default"
ROUNDS=5
CACHE_DIR=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --connection) PODMAN_CONNECTION="$2"; shift 2 ;;
    --rounds) ROUNDS="$2"; shift 2 ;;
    --cache-dir) CACHE_DIR="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

pcmd() { podman --connection "${PODMAN_CONNECTION}" "$@"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_HELPER="${WORKSPACE_DIR}/scripts/podman-cache-image.sh"
CACHE_DIR="${CACHE_DIR:-${WORKSPACE_DIR}/image-cache}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_DIR="${SCRIPT_DIR}/results/cache_persistent_${TIMESTAMP}"
mkdir -p "${RUN_DIR}"

cache_image() {
  local image="$1"
  if [ ! -x "${CACHE_HELPER}" ]; then
    echo "ERROR: cache helper not found: ${CACHE_HELPER}"
    return 1
  fi
  "${CACHE_HELPER}" --quiet --connection "${PODMAN_CONNECTION}" --platform linux/amd64 --cache-dir "${CACHE_DIR}" "${image}"
}

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   FEX-Emu Persistent Container Cache Test                    ║"
echo "║   ${TIMESTAMP}  Rounds: ${ROUNDS}"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

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

SUMMARY="${RUN_DIR}/summary.md"
cat > "${SUMMARY}" <<EOF
# FEX-Emu Persistent Container Cache Test

- **Date**: $(date)
- **Connection**: ${PODMAN_CONNECTION}
- **Rounds**: ${ROUNDS}
- **Method**: \`podman create\` + \`podman start\` + \`podman exec bash -c "loop"\` (internal loop, same as warmup)

EOF

# ─────────────────────────────────────────
# Test runner — uses internal loop inside a single exec call,
# matching warmup bench measurement methodology exactly.
# ─────────────────────────────────────────
run_persistent_test() {
  local test_id="$1"
  local test_name="$2"
  local image="$3"
  local cmd="$4"
  local timeout="${5:-120}"

  local cn="fex-pcache-${test_id}-$$"
  local log="${RUN_DIR}/${test_id}-${test_name//[\/\ ]/-}.log"

  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}[${test_id}] ${test_name}${NC}"
  echo -e "${CYAN}  Image: ${image}${NC}"
  echo -e "${CYAN}  Cmd:   ${cmd}${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # 1. Create persistent container (entrypoint override keeps it alive)
  echo "Creating container ${cn}..." | tee "${log}"
  pcmd create --name "${cn}" --arch amd64 --entrypoint /bin/sleep "${image}" infinity >> "${log}" 2>&1
  pcmd start "${cn}" >> "${log}" 2>&1
  sleep 2

  # 2. Build internal loop script (identical to warmup bench methodology)
  local inner_script=""
  inner_script+="for i in \$(seq 1 ${ROUNDS}); do "
  inner_script+="  echo \"--- Round \$i/${ROUNDS} ---\"; "
  inner_script+="  START=\$(date +%s%N); "
  inner_script+="  ${cmd}; "
  inner_script+="  RC=\$?; "
  inner_script+="  END=\$(date +%s%N); "
  inner_script+="  ELAPSED=\$(( (END - START) / 1000000 )); "
  inner_script+="  echo \"TIMING: round=\$i elapsed_ms=\${ELAPSED} exit=\${RC}\"; "
  inner_script+="done; "
  inner_script+="echo '=== COMPLETE ==='"

  # 3. Run all rounds in a single exec call
  timeout "${timeout}" podman --connection "${PODMAN_CONNECTION}" exec \
    -e FEX_APP_DATA_LOCATION=/tmp/fex-emu/ \
    -e FEX_APP_CONFIG_LOCATION=/tmp/fex-emu/ \
    -e FEX_APP_CACHE_LOCATION=/tmp/fex-emu/cache/ \
    "${cn}" \
    bash -c "${inner_script}" 2>&1 | tee "${log}"
  local overall_exit=${PIPESTATUS[0]}

  # 4. Extract timing data
  local times=()
  local exits=()
  while IFS= read -r line; do
    local ms rc
    ms=$(echo "$line" | sed -n 's/.*elapsed_ms=\([0-9]*\).*/\1/p')
    rc=$(echo "$line" | sed -n 's/.*exit=\([0-9]*\).*/\1/p')
    if [ -n "$ms" ]; then
      times+=("$ms")
      exits+=("$rc")
    fi
  done < <(grep "^TIMING:" "${log}")

  # 5. Cleanup
  pcmd rm -f "${cn}" >> "${log}" 2>&1

  # 6. Print results
  echo ""
  if [ ${#times[@]} -eq 0 ]; then
    echo -e "${RED}  ❌ No timing data collected (exit=${overall_exit})${NC}"
    echo "### ${test_id}: ${test_name}" >> "${SUMMARY}"
    echo "" >> "${SUMMARY}"
    echo "❌ Failed — no timing data (exit=${overall_exit})" >> "${SUMMARY}"
    echo "" >> "${SUMMARY}"
    return
  fi

  echo -e "${GREEN}  Results:${NC}"
  for idx in "${!times[@]}"; do
    local rn=$((idx + 1))
    local secs=$(echo "scale=1; ${times[$idx]} / 1000" | bc)
    local pct=""
    if [ $idx -gt 0 ] && [ "${times[0]}" -gt 0 ]; then
      pct=" ($(echo "scale=0; ${times[$idx]} * 100 / ${times[0]}" | bc)%)"
    fi
    local mark=""
    [ "${exits[$idx]}" -ne 0 ] && mark=" ❌"
    echo -e "    Round ${rn}: ${secs}s${pct}${mark}"
  done

  # Calculate speedup: R1 / min of last 3 rounds
  if [ ${#times[@]} -ge 3 ]; then
    local first=${times[0]}
    local n=${#times[@]}
    local tail_min=${times[$((n-1))]}
    for ti in $((n-2)) $((n-3)); do
      [ $ti -ge 0 ] && [ "${times[$ti]}" -lt "$tail_min" ] && tail_min=${times[$ti]}
    done
    if [ "$tail_min" -gt 0 ]; then
      local sp=$(echo "scale=1; $first / $tail_min" | bc)
      echo -e "    ${YELLOW}Speedup (R1 / min R$((n-2))-R${n}): ${sp}x${NC}"
    fi
  fi
  echo ""

  # 7. Write summary
  cat >> "${SUMMARY}" <<INNER
### ${test_id}: ${test_name}

- **Image**: \`${image}\`
- **Command**: \`${cmd}\`

| Round | Time | Exit | vs R1 |
|:-----:|-----:|:----:|:-----:|
INNER
  for idx in "${!times[@]}"; do
    local rn=$((idx + 1))
    local secs=$(echo "scale=1; ${times[$idx]} / 1000" | bc)
    local pct="baseline"
    if [ $idx -gt 0 ] && [ "${times[0]}" -gt 0 ]; then
      pct="$(echo "scale=0; ${times[$idx]} * 100 / ${times[0]}" | bc)%"
    fi
    echo "| ${rn} | ${secs}s | ${exits[$idx]} | ${pct} |" >> "${SUMMARY}"
  done
  echo "" >> "${SUMMARY}"
}

# ─────────────────────────────────────────
# Test Suite — selected by observed cache speedup from past logs
# Same workloads as run-cache-warmup-bench.sh for direct comparison.
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
# ─────────────────────────────────────────

echo -e "\n${YELLOW}▶ Persistent Container Cache Tests (${ROUNDS} rounds each)${NC}\n"

# W1: Fedora dnf check-update (~15x)
run_persistent_test "W1" "Fedora dnf check-update" \
  "docker.io/library/fedora:latest" \
  "dnf check-update -q 2>/dev/null; true" 600

# W2: Arch Linux pacman sync (~12x)
run_persistent_test "W2" "Arch pacman sync" \
  "docker.io/library/archlinux:latest" \
  "pacman -Sy --noconfirm >/dev/null 2>&1 && echo 'pacman sync done'" 600

# W3: Perl interpreter startup (~8x)
run_persistent_test "W3" "Perl startup" \
  "docker.io/library/perl:5-slim" \
  "perl -e 'print \"hello\\n\"'" 120

# W4: Ubuntu dpkg list (~7x)
run_persistent_test "W4" "Ubuntu dpkg list" \
  "docker.io/library/ubuntu:latest" \
  "dpkg -l | wc -l" 120

# W5: Python interpreter startup (~6x)
run_persistent_test "W5" "Python startup" \
  "docker.io/library/python:3-slim" \
  "python3 -c 'print(42)'" 120

# W6: rustc version check (~4x)
run_persistent_test "W6" "rustc version" \
  "docker.io/library/rust:latest" \
  "rustc -vV" 300

# W7: Fedora rpm verify (~3.7x)
run_persistent_test "W7" "Fedora rpm verify" \
  "docker.io/library/fedora:latest" \
  "rpm -V bash" 120

# ─────────────────────────────────────────
echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║   COMPLETE                              ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"
echo "Results: ${RUN_DIR}/"
cat "${SUMMARY}"
