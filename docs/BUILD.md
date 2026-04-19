# Building the FEX-Emu Machine OS Image from Source

This document describes how to build the FEX-Emu enabled Podman Machine OS image from source.

> [!NOTE]
> If you just want to use the image, no build is required. See the Quick Start section in [README.md](../README.md).

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Repository Layout](#repository-layout)
4. [Containerfile Structure](#containerfile-structure)
5. [Build Procedure](#build-procedure)
6. [Pushing to a Registry](#pushing-to-a-registry)
7. [Testing](#testing)
8. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

The image is built using a **3-stage multi-stage Containerfile**:

```
┌─────────────────────────────────────────────────────────────┐
│  Stage 1: fex-builder (fedora:43)                           │
│  • Clone tnk4on/FEX fex-emu branch                         │
│  • Build with cmake + ninja as static-pie                   │
│  → FEXInterpreter, FEXServer, FEXOfflineCompiler            │
├─────────────────────────────────────────────────────────────┤
│  Stage 2: podman-builder (fedora:43)                        │
│  • Clone tnk4on/podman fex-emu branch                       │
│  • Build with make podman                                   │
│  → Podman binary with io.podman.image.arch annotation       │
├─────────────────────────────────────────────────────────────┤
│  Stage 3: Final OS (fedora-coreos:stable)                   │
│  • Run upstream build_common.sh                             │
│  • Install patched Podman                                   │
│  • Install fex-emu RPM + RootFS                             │
│  • Remove QEMU x86/x86_64 binfmt (replace with FEX)        │
│  • Overwrite RPM binaries with FEX static-pie binaries      │
│  • Install OCI hook script and JSON                         │
│  • Install FEX activation systemd service                   │
│  → podman-machine.aarch64.applehv.raw.zst                   │
└─────────────────────────────────────────────────────────────┘
```

### Component Roles

| Component | Description |
|---|---|
| **FEXInterpreter** | Core JIT emulator for x86/x86_64 ELF binaries (static-pie) |
| **FEXServer** | Code cache management daemon. Automatically launched by FEXInterpreter via `fork+execvp` inside each container, communicating over AF_UNIX sockets |
| **Patched Podman** | Automatically adds `io.podman.image.arch` annotation to all containers, enabling architecture-based filtering in OCI hooks |
| **OCI hook** | `fex-emu-hook.sh` — injects FEX binary bind mounts only into amd64 containers (ARM64 containers have zero overhead) |
| **containers.conf** | Sets `FEX_APP_*` environment variables for all containers. Reflected in the OCI spec, so inherited by `podman exec` as well |
| **fex-activation.service** | Runs at first VM boot to perform EROFS loop mount, binfmt registration, and containers.conf setup |

---

## Prerequisites

| Item | Requirement |
|---|---|
| **Build host** | Fedora 43 ARM64 (aarch64) — SSH access to an ARM64 Linux server |
| **Root privileges** | Required by osbuild |
| **Disk space** | At least 50GB free |
| **Required packages** | podman, buildah, rpm-ostree, osbuild (standard in Fedora 43) |
| **Network** | GitHub (repository clone), Quay.io (base image pull) |

> [!IMPORTANT]
> Building on macOS is not possible. An ARM64 Linux build host is required.

---

## Repository Layout

Three repositories have changes on their `fex-emu` branches:

| Repository | Branch | Changes |
|---|---|---|
| **[tnk4on/podman-machine-os](https://github.com/tnk4on/podman-machine-os/tree/fex-emu)** | `fex-emu` | FEX build stages in Containerfile, OCI hook, activation service |
| **[tnk4on/FEX](https://github.com/tnk4on/FEX/tree/fex-emu)** | `fex-emu` | Container-aware code cache path resolution, ProcessPipe buffer fix, personality() fix |
| **[tnk4on/podman](https://github.com/tnk4on/podman/tree/fex-emu)** | `fex-emu` | `io.podman.image.arch` annotation auto-injection, FEX code cache settings (v5.8 based) |

### Repositories Cloned by Containerfile

Two repositories are cloned directly inside the Containerfile:

```dockerfile
# Stage 1: FEX
ARG FEX_BRANCH=fex-emu
RUN git clone --depth 1 --branch ${FEX_BRANCH} \
    https://github.com/tnk4on/FEX.git /src/FEX

# Stage 2: Podman
ARG PODMAN_REPO=https://github.com/tnk4on/podman.git
ARG PODMAN_BRANCH=fex-emu
RUN git clone --depth 1 --branch ${PODMAN_BRANCH} ${PODMAN_REPO} /src/podman
```

> krunkit and libkrun are macOS-side components and are not included in the image build.

---

## Containerfile Structure

### Stage 1: FEX Builder

Builds FEX-Emu as static-pie binaries on Fedora 43:

- **Base image**: `fedora:43`
- **Build tools**: clang, lld, cmake, ninja
- **Source**: `tnk4on/FEX` `fex-emu` branch (patches are integrated into the branch)
- **CMake options**:
  - `-DCMAKE_BUILD_TYPE=Release` (**required** — omitting this disables optimizations and degrades performance by 2–3x)
  - `-DBUILD_SHARED_LIBS=OFF` — static-pie build
  - `-DBUILD_THUNKS=OFF` `-DBUILD_TESTS=OFF` `-DBUILD_FEXCONFIG=OFF`
  - `-DENABLE_JEMALLOC=ON`
  - `-DCMAKE_EXE_LINKER_FLAGS=-static-pie`
- **Output**: `FEXInterpreter`, `FEXServer`, `FEXOfflineCompiler`

### Stage 2: Podman Builder

Builds the patched Podman binary:

- **Base image**: `fedora:43`
- **Source**: `tnk4on/podman` `fex-emu` branch (v5.8 based)
- **Changes**: Automatically adds `io.podman.image.arch` annotation to all containers
- **Build command**: `make podman BUILDTAGS="seccomp selinux systemd exclude_graphdriver_btrfs cni"`

### Stage 3: Final OS Image

Integrates all components into the Fedora CoreOS base image:

1. Run `build_common.sh` (upstream common build steps)
2. Install patched Podman to `/usr/bin/podman`
3. Install FEX-Emu RPM packages (`fex-emu`, `fex-emu-rootfs-fedora`)
4. Remove QEMU x86/x86_64 binfmt configs (replaced by FEX; QEMU for other architectures is preserved)
5. Install `fex-activation.service` / `fex-activation.sh`
6. Install OCI hook (`fex-emu-hook.sh`, `fex-emu-hook.json`)
7. Copy FEX static-pie binaries from Stage 1 (replacing RPM dynamic binaries)

> All FEX-related steps are gated by `if [ "$(uname -m)" = "aarch64" ]` and are automatically skipped on x86_64 builds.

---

## Build Procedure

### Step 1: Log in to the Build Server

```bash
ssh <build-server>
```

### Step 2: Update the Repository

```bash
cd <workdir>/podman-machine-os
git fetch origin
git checkout fex-emu
git submodule update --init

# Reset build.sh / util.sh / gather.sh to upstream v5.8
# (fex-emu branch changes are limited to the Containerfile and related files)
git checkout origin/v5.8 -- build.sh util.sh gather.sh
echo "build.sh/util.sh/gather.sh reset to origin/v5.8"
```

### Step 3: Pre-Build Preparation

```bash
# Temporarily set SELinux to permissive (required by osbuild)
setenforce 0

# Remove old output files (prevents zstd overwrite prompts)
rm -f <workdir>/podman-machine-os/outdir/*.zst <workdir>/podman-machine-os/outdir/*.tar

# Reclaim disk space
fstrim -v /

# Clear OSBuild cache (can consume several GB)
rm -rf /var/cache/osbuild* /var/tmp/osbuild* 2>/dev/null
echo "OSBuild cache cleared"

# Set TMPDIR (/tmp may be too small)
export TMPDIR=/var/tmp
```

### Step 4: Run the Build

`build.sh` is kept identical to upstream. Use `sed | bash` to temporarily build only the applehv platform:

```bash
cd <workdir>/podman-machine-os
sed -e '/^PLATFORMS=/c\PLATFORMS="applehv"' \
    -e '/^(/,/^) &>/d' \
    -e '/trap.*WSL/d' \
    -e '/wait -n/d' \
    build.sh | bash
```

**sed pattern explanation:**

| Pattern | Purpose |
|---|---|
| `/^PLATFORMS=/c\PLATFORMS="applehv"` | Restrict PLATFORMS to applehv only |
| `/^(/,/^) &>/d` | Remove the WSL build subshell block |
| `/trap.*WSL/d` | Remove the WSL job trap line |
| `/wait -n/d` | Remove the WSL job wait |

> [!IMPORTANT]
> `build.sh` itself is never modified. Piping through `sed | bash` preserves upstream compatibility.

### Step 5: Verify Output

```bash
ls -lh <workdir>/podman-machine-os/outdir/podman-machine.aarch64.applehv.raw.zst
```

Expected output: `podman-machine.aarch64.applehv.raw.zst` (approximately 2–3 GB)

---

## Pushing to a Registry

### Local Registry (Development)

If you have a local HTTP registry on the build server (e.g., `<build-server-ip>:5000`):

```bash
ssh <build-server> 'cd <workdir>/podman-machine-os && source util.sh && \
  OUTDIR=outdir && \
  TAG="<build-server-ip>:5000/podman/machine-os:5.8" && \
  DISK_IMG="${OUTDIR}/podman-machine.aarch64.applehv.raw.zst" && \
  buildah manifest rm "${TAG}" 2>/dev/null; \
  buildah manifest create "${TAG}" && \
  buildah manifest add --arch arm64 "${TAG}" \
    "containers-storage:${FULL_IMAGE_NAME_ARCH}" && \
  buildah manifest add --artifact --artifact-type="" \
    --os=linux --arch=aarch64 --annotation "disktype=applehv" \
    "${TAG}" "${DISK_IMG}" && \
  buildah manifest push --all --tls-verify=false \
    "${TAG}" "docker://${TAG}" && \
  echo "✅ Pushed to ${TAG}"'
```

### Quay.io (Public)

```bash
ssh <build-server> 'cd <workdir>/podman-machine-os && source util.sh && \
  OUTDIR=outdir && \
  QUAY_TAG="quay.io/tnk4on/machine-os:5.8" && \
  DISK_IMG="${OUTDIR}/podman-machine.aarch64.applehv.raw.zst" && \
  buildah manifest rm "${QUAY_TAG}" 2>/dev/null; \
  buildah manifest create "${QUAY_TAG}" && \
  buildah manifest add --arch arm64 "${QUAY_TAG}" \
    "containers-storage:${FULL_IMAGE_NAME_ARCH}" && \
  buildah manifest add --artifact --artifact-type="" \
    --os=linux --arch=aarch64 --annotation "disktype=applehv" \
    "${QUAY_TAG}" "${DISK_IMG}" && \
  buildah manifest push --all \
    "${QUAY_TAG}" "docker://${QUAY_TAG}" && \
  echo "✅ Pushed to ${QUAY_TAG}"'
```

### OCI Artifact Structure

The manifest pushed to the registry follows the same structure as upstream's `gather.sh`:

```
manifest index
├── arm64 ostree container image (rpm-ostree rechunked)
└── applehv disk artifact (podman-machine.aarch64.applehv.raw.zst)
    └── annotation: disktype=applehv
```

---

## Testing

### Create a VM

```bash
# From Quay.io (public)
podman machine init test \
  --image docker://quay.io/tnk4on/machine-os:5.8 --now

# From local registry (development)
podman machine init test \
  --image docker://<build-server-ip>:5000/podman/machine-os:5.8 \
  --tls-verify=false --now

# From file (when registry is unreachable)
scp <build-server>:<workdir>/podman-machine-os/outdir/podman-machine.aarch64.applehv.raw.zst /tmp/
podman machine init test --image-path /tmp/podman-machine.aarch64.applehv.raw.zst --now
```

> [!NOTE]
> When using `--now` with a non-default machine, add `-u=false` to prevent an interactive prompt that blocks non-interactive terminals.

### Basic Verification

```bash
# x86_64 emulation
podman run --rm --platform linux/amd64 alpine uname -m
# → x86_64

# ARM64 regression check
podman run --rm --platform linux/arm64 alpine uname -m
# → aarch64

# FEX binfmt handler verification
podman machine ssh test cat /proc/sys/fs/binfmt_misc/FEX-x86_64
# → enabled, interpreter: /usr/bin/FEXInterpreter, flags: POCF
```

### Test Script

```bash
# Full test suite (61 tests, 7 categories)
bash tests/test-fex.sh --connection test

# Specific categories
bash tests/test-fex.sh --connection test --category basic,env

# Environment variable tests only
bash tests/test-fex.sh --connection test --category env
```

### Cleanup

```bash
podman machine rm -f test
```

---

## Troubleshooting

### Build stalls

- **zstd overwrite prompt**: Verify that `rm -f outdir/*.zst outdir/*.tar` was run in Step 3
- **Insufficient disk space**: Check with `df -h /`. Reclaim with `fstrim -v /` or free space with `rm -rf /var/cache/osbuild*`

### FEXInterpreter is oversized (25MB)

`-DCMAKE_BUILD_TYPE=Release` may not be specified. A Release build is approximately 6MB. Check the cmake line in the Containerfile.

### `uname -m` returns `aarch64` inside a container

- binfmt handler not registered: check `cat /proc/sys/fs/binfmt_misc/FEX-x86_64`
- Verify `--platform linux/amd64` is specified
- Check OCI hook is enabled: `ls /etc/containers/oci/hooks.d/fex-emu-hook.json`

### OSBuild errors

```bash
# Clear all caches and retry
rm -rf /var/cache/osbuild* /var/tmp/osbuild*
setenforce 0
```

### Syncing build changes to local workspace

Files changed on the build server should be reflected locally:

> [!IMPORTANT]
> The SSoT (single source of truth) is the local repository. Changes should flow: local → GitHub → build server. Do not edit files directly on the build server.

```bash
# Check changes
ssh <build-server> "cd <workdir>/podman-machine-os && git status --short"

# Sync with rsync (for reference only — prefer git-based workflow)
rsync -avz --exclude='.git' --exclude='outdir' --exclude='rpms' \
  --exclude='build.sh.bak' --exclude='cache' \
  <build-server>:<workdir>/podman-machine-os/podman-image/ \
  repos/podman-machine-os/podman-image/
```
