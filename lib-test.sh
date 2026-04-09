#!/usr/bin/env bash
# lib-test.sh — Shared test library for FEX/QEMU test runners
# Source this file from test-fex.sh / test-qemu.sh
# Provides: run_test (5 modes), CLI parsing, print helpers, cache helpers

# --- Colors ---
_G='\033[0;32m'; _R='\033[0;31m'; _Y='\033[1;33m'; _C='\033[0;36m'; _N='\033[0m'

# --- Globals (set by parse_args) ---
CONNECTION=""
CONNECTION_NAME=""
PODMAN="podman"
CACHE_DIR=""
SSH_TIMEOUT=30
MACHINE=""
LIST_ONLY=false
CATEGORIES=""          # comma-sep or empty=default
TESTS=""               # comma-sep or empty=all

# --- Counters ---
PASS=0; FAIL=0; SKIP=0; TOTAL=0
RESULTS=()

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_HELPER="${WORKSPACE_DIR}/scripts/podman-cache-image.sh"
RESULT_DIR="${SCRIPT_DIR}/bench-results"

# =============================================================================
# CLI Parsing
# =============================================================================
parse_args() {
  CACHE_DIR="${IMAGE_CACHE_DIR:-${WORKSPACE_DIR}/image-cache}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --connection)   shift; CONNECTION="--connection $1"; CONNECTION_NAME="$1" ;;
      --connection=*) CONNECTION="--connection ${1#*=}"; CONNECTION_NAME="${1#*=}" ;;
      --machine)      shift; MACHINE="$1" ;;
      --machine=*)    MACHINE="${1#*=}" ;;
      --cache-dir)    shift; CACHE_DIR="$1" ;;
      --cache-dir=*)  CACHE_DIR="${1#*=}" ;;
      --timeout)      shift; SSH_TIMEOUT="$1" ;;
      --timeout=*)    SSH_TIMEOUT="${1#*=}" ;;
      --category)     shift; CATEGORIES="$1" ;;
      --category=*)   CATEGORIES="${1#*=}" ;;
      --test)         shift; TESTS="$1" ;;
      --test=*)       TESTS="${1#*=}" ;;
      --list)         LIST_ONLY=true ;;
      -h|--help)      show_help; exit 0 ;;
      *)              echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
  done

  PODMAN="podman $CONNECTION"
  # Default MACHINE from CONNECTION_NAME for ssh-based tests
  [[ -z "$MACHINE" && -n "$CONNECTION_NAME" ]] && MACHINE="$CONNECTION_NAME"
  [[ -z "$MACHINE" ]] && MACHINE="podman-machine-default"

  mkdir -p "${RESULT_DIR}"
}

# =============================================================================
# Category / Test Filtering
# =============================================================================
# Check if a category should run
category_enabled() {
  local cat="$1"
  [[ -z "$CATEGORIES" ]] && return 0  # no filter = all enabled
  [[ ",$CATEGORIES," == *",$cat,"* ]]
}

# Check if a specific test should run
test_enabled() {
  local id="$1"
  [[ -z "$TESTS" ]] && return 0  # no filter = all enabled
  [[ ",$TESTS," == *",$id,"* ]]
}


# =============================================================================
# Helpers
# =============================================================================
cache_image() {
  local image="$1"
  local platform="${2:-linux/amd64}"
  [[ ! -x "${CACHE_HELPER}" ]] && return 0
  if [[ -n "${CONNECTION_NAME}" ]]; then
    "${CACHE_HELPER}" --quiet --connection "${CONNECTION_NAME}" --platform "${platform}" --cache-dir "${CACHE_DIR}" "${image}"
  else
    "${CACHE_HELPER}" --quiet --platform "${platform}" --cache-dir "${CACHE_DIR}" "${image}"
  fi
}

ssh_cmd() {
  timeout "$SSH_TIMEOUT" podman machine ssh "$MACHINE" "$@" 2>/dev/null
}

assert_vm_running() {
  local state
  state=$(podman machine inspect "$MACHINE" --format '{{.State}}' 2>/dev/null || echo "unknown")
  if [[ "$state" != "running" ]]; then
    echo -e "${_R}ERROR: Machine '$MACHINE' is not running (state=$state)${_N}"
    exit 1
  fi
}

header() {
  echo ""
  echo -e "${_C}═══ $1 ═══${_N}"
  [[ -n "${LOGFILE:-}" ]] && { echo "" >> "$LOGFILE"; echo "═══ $1 ═══" >> "$LOGFILE"; }
}

# =============================================================================
# run_test — Unified test runner (5 modes)
# =============================================================================
# Modes:
#   grep   — run cmd, grep output for expected string
#   exit   — run cmd, check exit code == 0
#   fn     — run cmd, pipe output to check_fn
#   script — run external script, exit 0=PASS, 124=TIMEOUT, other=FAIL
#   ssh    — run command via podman machine ssh, check result
#
# Usage: run_test <id> <name> <mode> <cmd_or_script> [<expect_or_fn>] [<timeout>]
run_test() {
  local id="$1" name="$2" mode="$3" cmd="$4" expect="${5:-}" test_timeout="${6:-$SSH_TIMEOUT}"

  # Filtering
  test_enabled "$id" || return 0

  TOTAL=$((TOTAL + 1))
  printf "%-6s %-45s " "$id" "$name"

  [[ -n "${LOGFILE:-}" ]] && {
    echo "=== $id: $name ===" >> "$LOGFILE"
    echo "mode=$mode" >> "$LOGFILE"
  }

  local output="" exit_code=0

  case "$mode" in
    grep|exit|fn)
      [[ -n "${LOGFILE:-}" ]] && echo "\$ $cmd" >> "$LOGFILE"
      output=$(eval "$cmd" 2>&1) && exit_code=0 || exit_code=$?
      [[ -n "${LOGFILE:-}" ]] && { echo "$output" >> "$LOGFILE"; echo "exit_code=$exit_code" >> "$LOGFILE"; echo "" >> "$LOGFILE"; }

      case "$mode" in
        grep)
          if echo "$output" | grep -q "$expect"; then
            _pass "$id" "$name"
          else
            _fail "$id" "$name" "$(echo "$output" | tail -1 | head -c 60)"
          fi
          ;;
        exit)
          if [[ "$exit_code" -eq 0 ]]; then
            _pass "$id" "$name"
          else
            _fail "$id" "$name" "exit $exit_code"
          fi
          ;;
        fn)
          if eval "$expect" <<< "$output"; then
            _pass "$id" "$name"
          else
            _fail "$id" "$name" "exit=$exit_code, got: $(echo "$output" | tail -1 | head -c 60)"
          fi
          ;;
      esac
      ;;

    script)
      local script_path="$cmd"
      [[ -n "${LOGFILE:-}" ]] && echo "\$ bash $script_path (timeout=${test_timeout}s)" >> "$LOGFILE"
      local start_time=$(date +%s)
      output=$(timeout "$test_timeout" bash "$script_path" 2>&1) && exit_code=0 || exit_code=$?
      local duration=$(( $(date +%s) - start_time ))
      [[ -n "${LOGFILE:-}" ]] && { echo "$output" >> "$LOGFILE"; echo "exit_code=$exit_code duration=${duration}s" >> "$LOGFILE"; echo "" >> "$LOGFILE"; }

      if [[ $exit_code -eq 0 ]]; then
        _pass "$id" "$name" "${duration}s"
      elif [[ $exit_code -eq 124 ]]; then
        echo -e "${_Y}⏱️ TIMEOUT${_N} (${duration}s)"
        RESULTS+=("$id|$name|TIMEOUT|${duration}s")
        FAIL=$((FAIL + 1))
      else
        _fail "$id" "$name" "exit $exit_code (${duration}s)"
      fi
      ;;

    ssh)
      [[ -n "${LOGFILE:-}" ]] && echo "\$ ssh: $cmd" >> "$LOGFILE"
      output=$(ssh_cmd "$cmd" 2>/dev/null) && exit_code=0 || exit_code=$?
      [[ -n "${LOGFILE:-}" ]] && { echo "$output" >> "$LOGFILE"; echo "exit_code=$exit_code" >> "$LOGFILE"; echo "" >> "$LOGFILE"; }

      if [[ -n "$expect" ]]; then
        if echo "$output" | grep -q "$expect"; then
          _pass "$id" "$name" "$output"
        else
          _fail "$id" "$name" "got: $output"
        fi
      else
        if [[ $exit_code -eq 0 ]]; then
          _pass "$id" "$name" "$output"
        else
          _fail "$id" "$name" "exit $exit_code"
        fi
      fi
      ;;
  esac
}

# --- Internal result helpers ---
_pass() {
  local id="$1" name="$2" detail="${3:-}"
  echo -e "${_G}✅ PASS${_N}${detail:+ ($detail)}"
  RESULTS+=("$id|$name|PASS|$detail")
  PASS=$((PASS + 1))
}

_fail() {
  local id="$1" name="$2" detail="${3:-}"
  echo -e "${_R}❌ FAIL${_N}${detail:+ ($detail)}"
  RESULTS+=("$id|$name|FAIL|$detail")
  FAIL=$((FAIL + 1))
}

_skip() {
  local id="$1" name="$2" detail="${3:-}"
  echo -e "${_Y}⏭️ SKIP${_N}${detail:+ ($detail)}"
  RESULTS+=("$id|$name|SKIP|$detail")
  SKIP=$((SKIP + 1))
  TOTAL=$((TOTAL + 1))
}

# =============================================================================
# Summary
# =============================================================================
print_summary() {
  echo ""
  echo -e "${_C}═══════════════════════════════════════════════════${_N}"
  echo -e "  ${_G}$PASS passed${_N}  ${_R}$FAIL failed${_N}  ${_Y}$SKIP skipped${_N}  (total: $TOTAL)"
  echo -e "${_C}═══════════════════════════════════════════════════${_N}"
  echo ""
  echo "| ID | Test | Result | Notes |"
  echo "|----|------|:------:|-------|"
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r rid rname rresult rnotes <<< "$r"
    local icon=""
    case "$rresult" in
      PASS)    icon="✅ PASS" ;;
      FAIL)    icon="❌ FAIL" ;;
      SKIP)    icon="⏭️ SKIP" ;;
      TIMEOUT) icon="⏱️ TIMEOUT" ;;
    esac
    echo "| $rid | $rname | $icon | $rnotes |"
  done
  echo ""
  if [[ -n "${LOGFILE:-}" && -f "$LOGFILE" ]]; then
    local logsize
    logsize=$(wc -c < "$LOGFILE" 2>/dev/null | tr -d ' ')
    echo "Full log: $LOGFILE (${logsize} bytes)"
  fi
  [[ "$FAIL" -gt 0 ]] && return 1 || return 0
}
