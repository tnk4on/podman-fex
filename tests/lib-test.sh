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
TEST_MODE="rootless"      # rootless|rootful|both
ROOTFUL_CONNECTION_NAME=""
LIST_ONLY=false
CATEGORIES=""          # comma-sep or empty=default
TESTS=""               # comma-sep or empty=all

# --- Counters ---
PASS=0; FAIL=0; SKIP=0; XFAIL=0; TOTAL=0
RESULTS=()
START_EPOCH=0
INTERRUPTED=false

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_HELPER="${WORKSPACE_DIR}/scripts/podman-cache-image.sh"
RESULT_DIR="${SCRIPT_DIR}/results"

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
      --mode)         shift; TEST_MODE="$1" ;;
      --mode=*)       TEST_MODE="${1#*=}" ;;
      --rootful-connection)   shift; ROOTFUL_CONNECTION_NAME="$1" ;;
      --rootful-connection=*) ROOTFUL_CONNECTION_NAME="${1#*=}" ;;
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

  case "$TEST_MODE" in
    rootless|rootful|both) ;;
    *)
      echo "Invalid --mode: $TEST_MODE (expected: rootless|rootful|both)"
      exit 1
      ;;
  esac

  PODMAN="podman $CONNECTION"
  # Default MACHINE from CONNECTION_NAME for ssh-based tests
  if [[ -z "$MACHINE" && -n "$CONNECTION_NAME" ]]; then
    MACHINE="$CONNECTION_NAME"
    # Rootful connections are commonly named <machine>-root.
    [[ "$MACHINE" == *-root ]] && MACHINE="${MACHINE%-root}"
  fi
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
  _log ""
  _log "═══ $1 ═══"
}

# Write plain text to LOGFILE (no color codes)
_log() {
  [[ -n "${LOGFILE:-}" ]] && echo "$*" >> "$LOGFILE"
}

_sanitize_detail() {
  local detail="$1"
  detail="${detail//$'\r'/ }"
  detail="${detail//$'\n'/ }"
  detail="${detail//$'\t'/ }"
  while [[ "$detail" == *"  "* ]]; do
    detail="${detail//  / }"
  done
  detail="${detail#${detail%%[![:space:]]*}}"
  detail="${detail%${detail##*[![:space:]]}}"
  printf "%s" "$detail"
}

# Signal handler: print partial summary on interrupt
_on_interrupt() {
  INTERRUPTED=true
  echo ""
  echo -e "${_R}⚠️  Test interrupted (signal received)${_N}"
  _log ""
  _log "⚠️  Test interrupted (signal received)"
  print_summary
  exit 130
}

# Setup signal traps — call after LOGFILE is set
setup_traps() {
  START_EPOCH=$(date +%s)
  trap _on_interrupt INT TERM
  trap '' PIPE  # Ignore SIGPIPE to prevent tee-related interruptions
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

  _log "=== $id: $name ==="
  _log "mode=$mode"

  local output="" exit_code=0

  case "$mode" in
    grep|exit|fn)
      _log "\$ $cmd"
      output=$(timeout "${test_timeout}" bash -c "$cmd" 2>&1) && exit_code=0 || exit_code=$?
      _log "$output"
      _log "exit_code=$exit_code"
      _log ""

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
      _log "\$ bash $script_path (timeout=${test_timeout}s)"
      local start_time=$(date +%s)
      output=$(timeout "$test_timeout" bash "$script_path" 2>&1) && exit_code=0 || exit_code=$?
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
      ;;

    ssh)
      _log "\$ ssh: $cmd"
      output=$(ssh_cmd "$cmd" 2>/dev/null) && exit_code=0 || exit_code=$?
      _log "$output"
      _log "exit_code=$exit_code"
      _log ""

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
  detail="$(_sanitize_detail "$detail")"
  echo -e "${_G}✅ PASS${_N}${detail:+ ($detail)}"
  _log "  ✅ PASS $id $name${detail:+ ($detail)}"
  RESULTS+=("$id|$name|PASS|$detail")
  PASS=$((PASS + 1))
}

_fail() {
  local id="$1" name="$2" detail="${3:-}"
  detail="$(_sanitize_detail "$detail")"
  echo -e "${_R}❌ FAIL${_N}${detail:+ ($detail)}"
  _log "  ❌ FAIL $id $name${detail:+ ($detail)}"
  RESULTS+=("$id|$name|FAIL|$detail")
  FAIL=$((FAIL + 1))
}

_skip() {
  local id="$1" name="$2" detail="${3:-}"
  detail="$(_sanitize_detail "$detail")"
  echo -e "${_Y}⏭️ SKIP${_N}${detail:+ ($detail)}"
  _log "  ⏭️ SKIP $id $name${detail:+ ($detail)}"
  RESULTS+=("$id|$name|SKIP|$detail")
  SKIP=$((SKIP + 1))
  TOTAL=$((TOTAL + 1))
}

_xfail() {
  local id="$1" name="$2" detail="${3:-}"
  detail="$(_sanitize_detail "$detail")"
  echo -e "${_Y}⚠️ XFAIL${_N}${detail:+ ($detail)}"
  _log "  ⚠️ XFAIL $id $name${detail:+ ($detail)}"
  RESULTS+=("$id|$name|XFAIL|$detail")
  XFAIL=$((XFAIL + 1))
}

# =============================================================================
# Summary
# =============================================================================
print_summary() {
  local elapsed=""
  if [[ "$START_EPOCH" -gt 0 ]]; then
    local now
    now=$(date +%s)
    local secs=$((now - START_EPOCH))
    elapsed=" in ${secs}s"
  fi

  local xfail_str=""
  [[ "$XFAIL" -gt 0 ]] && xfail_str="  $XFAIL xfail"
  local summary_line="$PASS passed  $FAIL failed  $SKIP skipped${xfail_str}  (total: $TOTAL${elapsed})"
  echo ""
  echo -e "${_C}═══════════════════════════════════════════════════${_N}"
  echo -e "  ${_G}$PASS passed${_N}  ${_R}$FAIL failed${_N}  ${_Y}$SKIP skipped${_N}${XFAIL:+  ${_Y}$XFAIL xfail${_N}}  (total: $TOTAL${elapsed})"
  if $INTERRUPTED; then
    echo -e "  ${_R}⚠️  INTERRUPTED — results are partial${_N}"
  fi
  echo -e "${_C}═══════════════════════════════════════════════════${_N}"
  echo ""

  _log ""
  _log "═══════════════════════════════════════════════════"
  _log "  $summary_line"
  $INTERRUPTED && _log "  ⚠️  INTERRUPTED — results are partial"
  _log "═══════════════════════════════════════════════════"
  _log ""

  echo "| ID | Test | Result | Notes |"
  echo "|----|------|:------:|-------|"
  _log "| ID | Test | Result | Notes |"
  _log "|----|------|:------:|-------|"
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r rid rname rresult rnotes <<< "$r"
    local icon=""
    case "$rresult" in
      PASS)    icon="✅ PASS" ;;
      FAIL)    icon="❌ FAIL" ;;
      SKIP)    icon="⏭️ SKIP" ;;
      TIMEOUT) icon="⏱️ TIMEOUT" ;;
      XFAIL)   icon="⚠️ XFAIL" ;;
    esac
    echo "| $rid | $rname | $icon | $rnotes |"
    _log "| $rid | $rname | $icon | $rnotes |"
  done
  echo ""
  _log ""
  if [[ -n "${LOGFILE:-}" && -f "$LOGFILE" ]]; then
    local logsize
    logsize=$(wc -c < "$LOGFILE" 2>/dev/null | tr -d ' ')
    echo "Full log: $LOGFILE (${logsize} bytes)"
    _log "Full log: $LOGFILE (${logsize} bytes)"
  fi
  [[ "$FAIL" -gt 0 ]] && return 1 || return 0
}
