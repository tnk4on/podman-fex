#!/usr/bin/env bash
# switch-backend.sh — FEX / QEMU backend switcher for Podman Machine
#
# Creates and manages two separate VMs:
#   - FEX VM:  Custom image (quay.io/tnk4on/machine-os:5.8) with FEX-Emu
#   - QEMU VM: Default CoreOS image with qemu-user-static
#
# Usage:
#   ./switch-backend.sh fex              # Create/start FEX VM, run FEX tests
#   ./switch-backend.sh qemu             # Create/start QEMU VM, run QEMU tests
#   ./switch-backend.sh fex  --test-only # Skip VM creation, just run tests
#   ./switch-backend.sh qemu --test-only # Skip VM creation, just run tests
#   ./switch-backend.sh status           # Show both VMs status
#   ./switch-backend.sh clean            # Remove both VMs
#   ./switch-backend.sh clean-fex        # Remove FEX VM only
#   ./switch-backend.sh clean-qemu       # Remove QEMU VM only
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}/tests"

# --- VM Configuration ---
FEX_VM="test"
FEX_IMAGE="docker://quay.io/tnk4on/machine-os:5.8"
QEMU_VM="test-qemu"
# QEMU uses default CoreOS image (no --image flag)

# --- Colors ---
_G='\033[0;32m'; _R='\033[0;31m'; _Y='\033[1;33m'; _C='\033[0;36m'; _N='\033[0m'

# =============================================================================
# Helpers
# =============================================================================
die() { echo -e "${_R}ERROR: $*${_N}" >&2; exit 1; }
info() { echo -e "${_C}>>> $*${_N}"; }
ok() { echo -e "${_G}✅ $*${_N}"; }

vm_state() {
  podman machine inspect "$1" --format '{{.State}}' 2>/dev/null || echo "not_created"
}

kill_machine_processes() {
  info "Stopping remaining processes..."
  pkill -9 -f krunkit 2>/dev/null || true
  pkill -9 -f gvproxy 2>/dev/null || true
  pkill -9 -f "podman.*machine" 2>/dev/null || true
  pkill -9 -f vfkit 2>/dev/null || true
  sleep 1
}

clean_vm() {
  local name="$1"
  local state
  state=$(vm_state "$name")
  if [[ "$state" != "not_created" ]]; then
    info "Removing VM: $name (state=$state)"
    podman machine stop "$name" 2>/dev/null || true
    podman machine rm -f "$name" 2>/dev/null || true
  fi
}

stop_other_vms() {
  local keep="$1"
  local running
  running=$(podman machine list --format '{{.Name}}:{{.Running}}' 2>/dev/null || true)
  while IFS= read -r line; do
    local vm_name="${line%%:*}"
    vm_name="${vm_name%\*}"  # strip default-machine asterisk
    local is_running="${line##*:}"
    if [[ "$is_running" == "true" && "$vm_name" != "$keep" ]]; then
      info "Stopping VM '$vm_name' (libkrun allows only one VM at a time)"
      podman machine stop "$vm_name" 2>/dev/null || true
      sleep 1
    fi
  done <<< "$running"
}

ensure_vm() {
  local name="$1" image_flag="${2:-}"
  local state
  state=$(vm_state "$name")

  case "$state" in
    running)
      ok "VM '$name' is already running"
      return 0
      ;;
    stopped)
      stop_other_vms "$name"
      info "Starting existing VM: $name"
      podman machine start "$name"
      return $?
      ;;
    not_created)
      stop_other_vms "$name"
      info "Creating VM: $name"

      if [[ -n "$image_flag" ]]; then
        podman machine init "$name" $image_flag --now
      else
        podman machine init "$name" --now
      fi
      return $?
      ;;
    *)
      die "Unknown VM state: $state for $name"
      ;;
  esac
}

wait_vm_ready() {
  local name="$1"
  info "Waiting for VM '$name' to be ready..."
  local i=0
  while [[ $i -lt 30 ]]; do
    if podman machine ssh "$name" "echo ready" 2>/dev/null | grep -q "ready"; then
      ok "VM '$name' is ready"
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  die "VM '$name' did not become ready in 60s"
}

# =============================================================================
# Commands
# =============================================================================
cmd_status() {
  echo -e "${_C}══════════════════════════════════════════════════${_N}"
  echo -e "${_C} Backend Status${_N}"
  echo -e "${_C}══════════════════════════════════════════════════${_N}"
  echo ""
  local fex_state qemu_state
  fex_state=$(vm_state "$FEX_VM")
  qemu_state=$(vm_state "$QEMU_VM")

  printf "  %-12s %-15s %s\n" "Backend" "VM" "State"
  printf "  %-12s %-15s %s\n" "-------" "---" "-----"
  printf "  %-12s %-15s %s\n" "FEX" "$FEX_VM" "$fex_state"
  printf "  %-12s %-15s %s\n" "QEMU" "$QEMU_VM" "$qemu_state"
  echo ""

  if [[ "$fex_state" == "running" ]]; then
    local handler
    handler=$(podman machine ssh "$FEX_VM" "ls /proc/sys/fs/binfmt_misc/ 2>/dev/null | grep -iE 'fex|qemu'" 2>/dev/null || echo "unknown")
    echo "  FEX VM binfmt: $handler"
  fi
  if [[ "$qemu_state" == "running" ]]; then
    local handler
    handler=$(podman machine ssh "$QEMU_VM" "ls /proc/sys/fs/binfmt_misc/ 2>/dev/null | grep -iE 'fex|qemu'" 2>/dev/null || echo "unknown")
    echo "  QEMU VM binfmt: $handler"
  fi
  echo ""
}

cmd_fex() {
  local test_only=false
  local extra_args=()
  for arg in "$@"; do
    case "$arg" in
      --test-only) test_only=true ;;
      *) extra_args+=("$arg") ;;
    esac
  done

  echo -e "${_C}══════════════════════════════════════════════════${_N}"
  echo -e "${_C} Switching to FEX backend${_N}"
  echo -e "${_C}══════════════════════════════════════════════════${_N}"
  echo ""

  if $test_only; then
    # --test-only: still need to ensure the right VM is running
    stop_other_vms "$FEX_VM"
    local st
    st=$(vm_state "$FEX_VM")
    if [[ "$st" == "stopped" ]]; then
      info "Starting VM: $FEX_VM"
      podman machine start "$FEX_VM"
      wait_vm_ready "$FEX_VM"
    elif [[ "$st" == "running" ]]; then
      ok "VM '$FEX_VM' is already running"
    else
      die "FEX VM '$FEX_VM' does not exist. Run without --test-only to create it."
    fi
  else
    ensure_vm "$FEX_VM" "--image $FEX_IMAGE"
    wait_vm_ready "$FEX_VM"
  fi

  info "Running FEX test suite..."
  bash "${TESTS_DIR}/test-fex.sh" --connection "$FEX_VM" "${extra_args[@]}"
}

cmd_qemu() {
  local test_only=false
  local extra_args=()
  for arg in "$@"; do
    case "$arg" in
      --test-only) test_only=true ;;
      *) extra_args+=("$arg") ;;
    esac
  done

  echo -e "${_C}══════════════════════════════════════════════════${_N}"
  echo -e "${_C} Switching to QEMU backend${_N}"
  echo -e "${_C}══════════════════════════════════════════════════${_N}"
  echo ""

  if $test_only; then
    stop_other_vms "$QEMU_VM"
    local st
    st=$(vm_state "$QEMU_VM")
    if [[ "$st" == "stopped" ]]; then
      info "Starting VM: $QEMU_VM"
      podman machine start "$QEMU_VM"
      wait_vm_ready "$QEMU_VM"
    elif [[ "$st" == "running" ]]; then
      ok "VM '$QEMU_VM' is already running"
    else
      die "QEMU VM '$QEMU_VM' does not exist. Run without --test-only to create it."
    fi
  else
    ensure_vm "$QEMU_VM"
    wait_vm_ready "$QEMU_VM"
  fi

  info "Running QEMU test suite..."
  bash "${TESTS_DIR}/test-qemu.sh" --connection "$QEMU_VM" "${extra_args[@]}"
}

cmd_clean() {
  info "Cleaning all VMs..."
  kill_machine_processes
  clean_vm "$FEX_VM"
  clean_vm "$QEMU_VM"
  ok "All VMs cleaned"
}

cmd_clean_fex() {
  info "Cleaning FEX VM..."
  clean_vm "$FEX_VM"
  ok "FEX VM cleaned"
}

cmd_clean_qemu() {
  info "Cleaning QEMU VM..."
  clean_vm "$QEMU_VM"
  ok "QEMU VM cleaned"
}

# =============================================================================
# Usage
# =============================================================================
usage() {
  cat <<'EOF'
switch-backend.sh — FEX / QEMU backend switcher

Usage:
  switch-backend.sh fex  [--test-only] [test-fex.sh args...]
  switch-backend.sh qemu [--test-only] [test-qemu.sh args...]
  switch-backend.sh status
  switch-backend.sh clean
  switch-backend.sh clean-fex
  switch-backend.sh clean-qemu

Commands:
  fex         Create/start FEX VM and run FEX tests
  qemu        Create/start QEMU VM and run QEMU tests
  status      Show both VMs status
  clean       Remove both VMs
  clean-fex   Remove FEX VM only
  clean-qemu  Remove QEMU VM only

Options:
  --test-only   Skip VM creation, just run tests on existing VM

Examples:
  # Full cycle: create QEMU VM + run all tests
  switch-backend.sh qemu

  # Only run tests on existing FEX VM (infra+basic categories)
  switch-backend.sh fex --test-only --category infra,basic

  # Switch to QEMU, run specific tests
  switch-backend.sh qemu --test I16,B01

  # Check status of both VMs
  switch-backend.sh status

  # Clean everything and start fresh
  switch-backend.sh clean
  switch-backend.sh fex
  switch-backend.sh qemu
EOF
}

# =============================================================================
# Main
# =============================================================================
case "${1:-}" in
  fex)        shift; cmd_fex "$@" ;;
  qemu)       shift; cmd_qemu "$@" ;;
  status)     cmd_status ;;
  clean)      cmd_clean ;;
  clean-fex)  cmd_clean_fex ;;
  clean-qemu) cmd_clean_qemu ;;
  -h|--help)  usage ;;
  "")         usage; exit 1 ;;
  *)          die "Unknown command: $1. Run with --help for usage." ;;
esac
