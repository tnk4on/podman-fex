#!/bin/bash
# Cross-backend benchmark: Run all workloads on FEX/QEMU/Rosetta
# Usage:
#   ./compare.sh [--connection <name>] [--label <backend>] [--iterations <N>] [--cache-dir <dir>] [--env KEY=VALUE]...
#
# Example:
#   ./compare.sh --connection test --label fex --iterations 10
#   ./compare.sh --connection bench-qemu --label qemu --iterations 10
#   ./compare.sh --connection bench-rosetta --label rosetta --iterations 10
#   ./compare.sh --connection test --label fex --iterations 10 --cache-dir ./image-cache
#   ./compare.sh --connection test --label fex-smc-none --iterations 10 --env "FEX_SMCCHECKS=none"

set -uo pipefail

# Defaults
PODMAN_CONNECTION=""
LABEL="unknown"
ITERATIONS=10
CACHE_DIR=""
EXTRA_ENVS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --connection) PODMAN_CONNECTION="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --iterations) ITERATIONS="$2"; shift 2 ;;
    --cache-dir) CACHE_DIR="$2"; shift 2 ;;
    --env) EXTRA_ENVS+=("$2"); shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
if [ -z "${CACHE_DIR}" ]; then
  CACHE_DIR="${WORKSPACE_DIR}/image-cache"
fi
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="${SCRIPT_DIR}/results"
mkdir -p "${RESULT_DIR}"
OUTFILE="${RESULT_DIR}/${LABEL}-${TIMESTAMP}.tsv"
LOGFILE="${RESULT_DIR}/${LABEL}-${TIMESTAMP}.log"

if [ -n "${PODMAN_CONNECTION}" ]; then
  PCMD=(podman --connection "${PODMAN_CONNECTION}")
else
  PCMD=(podman)
fi
pcmd() { "${PCMD[@]}" "$@"; }
tcmd() { timeout "$1" "${PCMD[@]}" "${@:2}"; }

echo "============================================="
echo " Cross-Backend Benchmark: ${LABEL}"
echo " Connection: ${PODMAN_CONNECTION:-default}"
echo " Iterations: ${ITERATIONS}"
echo " Cache dir:  ${CACHE_DIR:-none}"
echo " Extra env:  ${EXTRA_ENVS[*]:-none}"
echo " Timestamp: ${TIMESTAMP}"
echo "============================================="
echo ""

# Helper: convert image ref to safe filename
img_to_cachefile() {
  local img="$1"
  echo "${img//[\/:]/_}.tar"
}

# Header
printf "workload\timage\t" > "${OUTFILE}"
for i in $(seq 1 "${ITERATIONS}"); do
  printf "run%d_ms\t" "$i" >> "${OUTFILE}"
done
printf "min_ms\tstatus\n" >> "${OUTFILE}"

# ─────────────────────────────────────────
# Run a single benchmark workload using podman run --rm
# ALL phases (setup + measurement) run inside a SINGLE
# container process via bash -c, so FEX JIT code cache accumulates
# correctly. podman exec does NOT inherit OCI hook environment
# variables (FEX_APP_CACHE_LOCATION etc.), breaking code cache.
# ─────────────────────────────────────────
BENCH_SEQ=0
run_bench() {
  local workload="$1"
  local image="$2"
  local setup_cmd="$3"  # run once before measurement
  local bench_cmd="$4"
  local timeout_sec="${5:-120}"

  BENCH_SEQ=$((BENCH_SEQ + 1))

  echo "──────────────────────────────────────────"
  echo "[${BENCH_SEQ}] ${workload}"
  echo "Image:    ${image}"
  echo "Command:  ${bench_cmd}"
  echo "──────────────────────────────────────────"

  local cn="bench-${LABEL}-${BENCH_SEQ}-$$"
  local times=()
  local status="ok"

  # Build in-container script: setup + measurement in a single process
  local inner=""

  # Setup phase (if any)
  if [ -n "${setup_cmd}" ]; then
    inner+="echo 'SETUP:start'; "
    inner+="${setup_cmd}; "
    inner+="SETUP_RC=\$?; "
    inner+="if [ \$SETUP_RC -ne 0 ]; then echo 'SETUP:fail'; exit 1; fi; "
    inner+="echo 'SETUP:done'; "
  fi

  # Measurement iterations
  inner+="for i in \$(seq 1 ${ITERATIONS}); do "
  inner+="START=\$(date +%s%N); "
  inner+="${bench_cmd} > /dev/null 2>&1; "
  inner+="RC=\$?; "
  inner+="END=\$(date +%s%N); "
  inner+="MS=\$(( (END - START) / 1000000 )); "
  inner+="echo \"RESULT:\${MS}:\${RC}\"; "
  inner+="done"

  # Calculate total timeout: setup + iterations
  local total_timeout=$((timeout_sec * (ITERATIONS + 2)))

  # Execute everything in a single podman run --rm
  local output
  # Build env flags
  local env_flags=()
  if [ ${#EXTRA_ENVS[@]} -gt 0 ]; then
    for e in "${EXTRA_ENVS[@]}"; do
      env_flags+=(-e "$e")
    done
  fi

  if [ ${#env_flags[@]} -gt 0 ]; then
    output=$(timeout "${total_timeout}" "${PCMD[@]}" run --rm --name "${cn}" \
      "${env_flags[@]}" --arch amd64 "${image}" bash -c "${inner}" 2>&1) || true
  else
    output=$(timeout "${total_timeout}" "${PCMD[@]}" run --rm --name "${cn}" \
      --arch amd64 "${image}" bash -c "${inner}" 2>&1) || true
  fi

  # Report setup
  if [ -n "${setup_cmd}" ]; then
    if echo "${output}" | grep -q "^SETUP:fail"; then
      echo "  Setup: FAIL"
      printf "%s\t%s\t" "${workload}" "${image}" >> "${OUTFILE}"
      for i in $(seq 1 "${ITERATIONS}"); do printf "0\t" >> "${OUTFILE}"; done
      printf "0\tfail-setup\n" >> "${OUTFILE}"
      echo ""
      return
    elif echo "${output}" | grep -q "^SETUP:done"; then
      echo "  Setup: ok"
    fi
  fi

  # Parse and report measurement results
  while IFS= read -r line; do
    local ms rc
    ms=$(echo "${line}" | cut -d: -f2)
    rc=$(echo "${line}" | cut -d: -f3)
    if [ -z "${ms}" ]; then
      status="fail"
      times+=("0")
    else
      local secs
      secs=$(echo "scale=3; ${ms} / 1000" | bc)
      local run_idx=$((${#times[@]} + 1))
      echo "  Run ${run_idx}/${ITERATIONS}: ${secs}s (exit=${rc})"
      times+=("${ms}")
      if [ "${rc}" != "0" ] && [ "${status}" = "ok" ]; then
        status="exit${rc}"
      fi
    fi
  done < <(echo "${output}" | grep "^RESULT:")

  # Handle case where no results were parsed
  if [ ${#times[@]} -eq 0 ]; then
    echo "  FAIL (timeout or error)"
    echo "=== ${workload} ===" >> "${LOGFILE}"
    echo "${output}" >> "${LOGFILE}"
    echo "---" >> "${LOGFILE}"
    status="fail"
    for i in $(seq 1 "${ITERATIONS}"); do times+=("0"); done
  fi

  # Calculate min
  local min_val=0
  if [ "${status}" != "fail" ] && [ ${#times[@]} -gt 0 ]; then
    min_val=$(printf '%s\n' "${times[@]}" | sort -n | head -1)
  fi

  # Write TSV
  printf "%s\t%s\t" "${workload}" "${image}" >> "${OUTFILE}"
  for t in "${times[@]}"; do
    printf "%s\t" "$t" >> "${OUTFILE}"
  done
  printf "%s\t%s\n" "${min_val}" "${status}" >> "${OUTFILE}"

  echo "  → Min: ${min_val}ms [${status}]"
  echo ""
}

# ─────────────────────────────────────────
# Pre-pull images to avoid measuring pull time
# ─────────────────────────────────────────
echo "Pulling images..."
IMAGES=(
  "docker.io/library/python:3-slim"
  "docker.io/library/perl:5-slim"
  "docker.io/library/ruby:3-slim"
  "docker.io/library/fedora:latest"
  "docker.io/library/ubuntu:latest"
  "docker.io/library/archlinux:latest"
  "docker.io/library/gcc:latest"
  "docker.io/library/rust:latest"
  "docker.io/library/r-base:latest"
  "docker.io/library/eclipse-temurin:latest"
  "docker.io/library/node:lts-slim"
  "mcr.microsoft.com/dotnet/sdk:latest"
)

if [ -n "${CACHE_DIR}" ]; then
  mkdir -p "${CACHE_DIR}"
  echo "  (cache-dir: ${CACHE_DIR})"
fi

for img in "${IMAGES[@]}"; do
  echo -n "  ${img}... "
  local_loaded=false

  # Try loading from local cache first
  if [ -n "${CACHE_DIR}" ]; then
    cachefile="${CACHE_DIR}/$(img_to_cachefile "${img}")"
    if [ -f "${cachefile}" ]; then
      if pcmd load < "${cachefile}" > /dev/null 2>&1; then
        echo "ok (cached)"
        local_loaded=true
      else
        echo -n "cache-load-fail, pulling... "
      fi
    fi
  fi

  # Pull from registry if not loaded from cache
  if [ "${local_loaded}" = false ]; then
    if pcmd pull --platform linux/amd64 "${img}" > /dev/null 2>&1; then
      echo -n "ok"
      # Save to cache if cache-dir is set
      if [ -n "${CACHE_DIR}" ]; then
        cachefile="${CACHE_DIR}/$(img_to_cachefile "${img}")"
        if pcmd save --format oci-archive "${img}" > "${cachefile}" 2>/dev/null; then
          echo " (saved)"
        else
          rm -f "${cachefile}"
          echo " (save-fail)"
        fi
      else
        echo ""
      fi
    else
      echo "FAIL"
    fi
  fi
done
echo ""

# ─────────────────────────────────────────
# Workloads: 20 practical benchmarks in 7 categories
# ─────────────────────────────────────────
echo "============================================="
echo " Running ${ITERATIONS} iterations per workload"
echo "============================================="
echo ""

# ── Category 1: Interpreter startup ──────
echo "── Category 1: Interpreter startup ──"
echo ""

# 1. python3 startup
run_bench "python3 -c print(42)" "docker.io/library/python:3-slim" "" \
  "python3 -c 'print(42)'" 120

# 2. perl startup
run_bench "perl -e print" "docker.io/library/perl:5-slim" "" \
  "perl -e 'print 42'" 120

# 3. ruby startup
run_bench "ruby -e puts" "docker.io/library/ruby:3-slim" "" \
  "ruby -e 'puts 42'" 120

# ── Category 2: Package manager operations ──
echo "── Category 2: Package manager operations ──"
echo ""

# 4. rpm -V bash
run_bench "rpm -V bash" "docker.io/library/fedora:latest" "" \
  "rpm -V bash" 120

# 5. rpm -qa | wc -l
run_bench "rpm -qa | wc -l" "docker.io/library/fedora:latest" "" \
  "rpm -qa | wc -l" 120

# 6. dpkg -l | wc -l
run_bench "dpkg -l | wc -l" "docker.io/library/ubuntu:latest" "" \
  "dpkg -l | wc -l" 120

# 7. pacman -Sy
run_bench "pacman -Sy" "docker.io/library/archlinux:latest" "" \
  "rm -rf /var/lib/pacman/sync && pacman -Sy --noconfirm 2>/dev/null; true" 300

# 8. dnf repoquery (local RPM db, no network)
run_bench "dnf repoquery --installed" "docker.io/library/fedora:latest" "" \
  "dnf repoquery --installed --whatprovides /usr/bin/bash" 120

# ── Category 3: Compilation ──────────────
echo "── Category 3: Compilation ──"
echo ""

# 9. gcc hello.c
run_bench "gcc hello.c" "docker.io/library/gcc:latest" \
  "echo 'int main(){return 0;}' > /tmp/hello.c" \
  "gcc /tmp/hello.c -o /tmp/hello" 300

# 10. g++ -O2 STL
run_bench "g++ -O2 hello.cpp (STL)" "docker.io/library/gcc:latest" \
  "printf '#include <iostream>\n#include <vector>\n#include <algorithm>\nint main(){std::vector<int> v={3,1,2}; std::sort(v.begin(),v.end()); std::cout<<v[0]<<std::endl; return 0;}' > /tmp/hello.cpp" \
  "g++ -O2 /tmp/hello.cpp -o /tmp/hello" 600

# 11. make (Makefile build)
run_bench "make hello" "docker.io/library/gcc:latest" \
  "echo 'int main(){return 0;}' > /tmp/hello.c && printf 'hello: hello.c\n\tgcc -o hello hello.c\n' > /tmp/Makefile" \
  "cd /tmp && make -B hello 2>/dev/null" 300

# ── Category 4: Python ecosystem ─────────
echo "── Category 4: Python ecosystem ──"
echo ""

# 12. django manage.py check
run_bench "django manage.py check" "docker.io/library/python:3-slim" \
  "pip install django >/dev/null 2>&1 && django-admin startproject testproj /tmp/testproj" \
  "cd /tmp/testproj && python manage.py check" 300

# 13. ansible localhost ping
run_bench "ansible localhost ping" "docker.io/library/python:3-slim" \
  "pip install ansible-core >/dev/null 2>&1" \
  "ansible localhost -m ping -i localhost, -c local" 600

# 14. mypy type-check
run_bench "mypy type-check" "docker.io/library/python:3-slim" \
  "pip install mypy >/dev/null 2>&1" \
  "mypy -c 'x: int = 1'" 300

# ── Category 5: Build tools ──────────────
echo "── Category 5: Build tools ──"
echo ""

# 15. perl regex 10k
run_bench "perl regex 10k" "docker.io/library/perl:5-slim" "" \
  "perl -e 'for(1..10000){\"Hello World 12345\"=~/(\w+)\s+(\w+)\s+(\d+)/}; print \"done\"'" 120

# 16. rustc compile hello
run_bench "rustc compile hello" "docker.io/library/rust:latest" \
  "echo 'fn main(){println!(\"hello\")}' > /tmp/hello.rs" \
  "rustc --edition 2021 /tmp/hello.rs -o /tmp/hello" 300

# ── Category 6: System tools ─────────────
echo "── Category 6: System tools ──"
echo ""

# 17. Rscript
run_bench "Rscript sum(1:1000)" "docker.io/library/r-base:latest" "" \
  "Rscript -e 'cat(sum(1:1000))'" 300

# ─────────────────────────────────────────
# JIT-on-JIT runtimes (analysis target)
# Overhead: SMC detection (mprotect W^X cycle) +
#           deferred signal trampolining (SIGSEGV chain)
# Hardware TSO eliminates atomic expansion on libkrun.
# ─────────────────────────────────────────
echo "============================================="
echo " JIT-on-JIT runtimes (Java, Node, .NET)"
echo "============================================="
echo ""

# 18. java HelloWorld
run_bench "java HelloWorld" "docker.io/library/eclipse-temurin:latest" \
  "printf 'public class HelloWorld {\n  public static void main(String[] a) {\n    System.out.println(42);\n  }\n}\n' > /tmp/HelloWorld.java && javac /tmp/HelloWorld.java -d /tmp" \
  "java -cp /tmp HelloWorld" 300

# 19. node console.log
run_bench "node -e console.log(42)" "docker.io/library/node:lts-slim" "" \
  "node -e 'console.log(42)'" 300

# 20. dotnet --info
run_bench "dotnet --info" "mcr.microsoft.com/dotnet/sdk:latest" "" \
  "dotnet --info 2>&1" 600

echo "============================================="
echo " BENCHMARK COMPLETE: ${LABEL}"
echo "============================================="
echo "Results: ${OUTFILE}"
if [ -f "${LOGFILE}" ]; then
  echo "Log:     ${LOGFILE}"
else
  echo "Log:     (none — all workloads succeeded)"
fi
