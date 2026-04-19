#!/usr/bin/env bash
set -euo pipefail

# Cache-aware image fetch for Podman.
# - First tries local OCI archive cache (podman load)
# - Falls back to registry pull on cache miss
# - Saves pulled image back to cache archive
#
# Usage:
#   ./scripts/podman-cache-image.sh [--connection NAME] [--platform linux/amd64] [--cache-dir DIR] IMAGE

CONNECTION=""
PLATFORM=""
CACHE_DIR=""
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --connection) CONNECTION="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --cache-dir) CACHE_DIR="$2"; shift 2 ;;
    --quiet) QUIET=true; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: podman-cache-image.sh [--connection NAME] [--platform linux/amd64] [--cache-dir DIR] IMAGE
EOF
      exit 0
      ;;
    *) IMAGE="$1"; shift ;;
  esac
done

if [[ -z "${IMAGE:-}" ]]; then
  echo "ERROR: IMAGE is required" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_DIR="${CACHE_DIR:-${WORKSPACE_DIR}/image-cache}"
mkdir -p "${CACHE_DIR}"

PCMD=(podman)
if [[ -n "${CONNECTION}" ]]; then
  PCMD+=(--connection "${CONNECTION}")
fi

log() {
  if [[ "${QUIET}" != "true" ]]; then
    echo "$@"
  fi
}

img_to_cachefile() {
  local img="$1"
  local plat="$2"
  local base
  base="${img//[\/:]/_}"
  if [[ -n "${plat}" ]]; then
    base+="__${plat//\//_}"
  fi
  echo "${base}.tar"
}

CACHE_FILE="${CACHE_DIR}/$(img_to_cachefile "${IMAGE}" "${PLATFORM}")"

# 0) Check if the correct platform image already exists locally
#    Use `podman images --filter` to find images by reference, then check arch on each.
#    This avoids the single-tag-lookup problem when multiple arches coexist.
if [[ -n "${PLATFORM}" ]]; then
  wanted_arch="${PLATFORM#*/}"
  existing_ids=$("${PCMD[@]}" images --filter "reference=${IMAGE}" --format '{{.ID}}' --no-trunc 2>/dev/null || echo "")
  for img_id in $existing_ids; do
    got_arch=$("${PCMD[@]}" inspect "$img_id" --format '{{.Architecture}}' 2>/dev/null || echo "")
    if [[ "${got_arch}" == "${wanted_arch}" ]]; then
      log "cache: already-present ${IMAGE} (${PLATFORM})"
      exit 0
    fi
  done
fi

# 1) Cache hit: pull from OCI archive (preserves platform metadata)
if [[ -f "${CACHE_FILE}" ]]; then
  if "${PCMD[@]}" pull "oci-archive:${CACHE_FILE}" >/dev/null 2>&1; then
    log "cache: hit ${IMAGE}"
    exit 0
  fi
  # Fallback: try legacy load
  if "${PCMD[@]}" load -i "${CACHE_FILE}" >/dev/null 2>&1; then
    log "cache: hit-load ${IMAGE}"
    exit 0
  fi
  log "cache: load-failed ${IMAGE}, fallback to pull"
fi

# 2) Cache miss: pull from registry
PULL_ARGS=()
if [[ -n "${PLATFORM}" ]]; then
  PULL_ARGS+=(--platform "${PLATFORM}")
fi

if "${PCMD[@]}" pull ${PULL_ARGS[@]+"${PULL_ARGS[@]}"} "${IMAGE}" >/dev/null 2>&1; then
  log "cache: pull ${IMAGE}"
  # Save pulled image into local cache
  if "${PCMD[@]}" save --format oci-archive "${IMAGE}" > "${CACHE_FILE}" 2>/dev/null; then
    log "cache: saved ${CACHE_FILE}"
  else
    rm -f "${CACHE_FILE}"
  fi
  exit 0
fi

echo "ERROR: could not pull or load ${IMAGE}" >&2
exit 1
