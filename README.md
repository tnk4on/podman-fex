# podman-fex — FEX-Emu x86_64 Emulation for Podman Machine

> **Preview Release** — April 2026
> **Image**: `quay.io/tnk4on/machine-os:5.8`

Run x86_64 Linux containers on Apple Silicon Macs at near-native speed using [FEX-Emu](https://github.com/FEX-Emu/FEX) JIT emulation inside [Podman Machine](https://docs.podman.io/en/latest/markdown/podman-machine.1.html) (libkrun backend).

## Why FEX-Emu?

On Apple Silicon Macs, running `--platform linux/amd64` containers has been limited to QEMU user-mode emulation — which is slow and often crashes on complex workloads. This project replaces QEMU with **FEX-Emu**, a JIT-based x86_64 emulator [officially adopted by Fedora 42](https://fedoraproject.org/wiki/Changes/FEX), delivering:

| Feature | Description |
|---------|-------------|
| **JIT Code Cache** | Up to **13.8x speedup** on repeated runs within the same container |
| **Hardware TSO** | Leverages Apple Silicon's TSO mode for x86 memory model emulation |
| **OCI Hook Integration** | FEX mounts only into x86_64 containers; ARM64 has zero overhead |
| **SELinux Enforcing** | Runs with security policies fully enabled |
| **QEMU Multi-arch** | QEMU handlers preserved for s390x, ppc64le, riscv64, etc. |

### Compatibility Improvements

Tested against 13 known Podman x86_64 emulation issues ([details](https://github.com/containers/podman/issues?q=is%3Aissue+label%3Aapple-silicon)):

| Category | Issues | Fixed | Rate |
|----------|:------:|:-----:|:----:|
| Hang / Freeze | 4 | 4 | **100%** |
| QEMU SIGSEGV | 3 | 3 | **100%** |
| Build Failures | 4 | 3 | 75% |
| Overall | 13 | **9** | **69.2%** |

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Hardware** | Apple Silicon Mac (M1 / M2 / M3 / M4) |
| **macOS** | 14 (Sonoma) or later recommended |
| **Podman** | v5.8+ (`brew install podman` or [official PKG](https://podman.io/)) |
| **Provider** | `libkrun` (default on Podman 5.8 for macOS) |

### Check your provider

```bash
podman machine info --format '{{.Host.DefaultMachineProvider}}'
# Must show: libkrun
```

If it doesn't show `libkrun`:
```bash
mkdir -p ~/.config/containers
cat >> ~/.config/containers/containers.conf << 'EOF'
[machine]
provider = "libkrun"
EOF
```

> [!IMPORTANT]
> This image requires the **`libkrun`** provider. It does **not** work with Apple Virtualization.framework (`applehv`).

---

## Quick Start

### Option A: Clean Install (replace existing machine)

```bash
# Remove existing default machine
podman machine stop 2>/dev/null
podman machine rm -f 2>/dev/null

# Create FEX-Emu machine
podman machine init \
  --image docker://quay.io/tnk4on/machine-os:5.8 \
  --disk-size 100 --memory 4096 --cpus 4 --now
```

### Option B: Side-by-Side (keep existing machine)

```bash
# Create a separate machine named "fex"
podman machine init fex \
  --image docker://quay.io/tnk4on/machine-os:5.8 \
  --disk-size 100 --memory 4096 --cpus 4 --now

# Use --connection flag for all commands
podman --connection fex run --rm --platform linux/amd64 alpine uname -m
```

> FEX-Emu RootFS and binfmt handlers are automatically set up on first boot (takes a few seconds).

### Verify it works

```bash
# x86_64 container
podman run --rm --platform linux/amd64 alpine uname -m
# → x86_64

# ARM64 container (regression check)
podman run --rm --platform linux/arm64 alpine uname -m
# → aarch64
```

---

## What to Test

We'd appreciate feedback on the following test items. Please report results using the [feedback template](#feedback) below.

### 🟢 Basic Tests (required, ~5 min)

| # | Test | Command | Expected |
|---|------|---------|----------|
| T1 | x86_64 container | `podman run --rm --platform linux/amd64 alpine uname -m` | `x86_64` |
| T2 | ARM64 regression | `podman run --rm --platform linux/arm64 alpine uname -m` | `aarch64` |
| T3 | Stability (5x) | See below | All `x86_64` |
| T4 | Fedora x86_64 | `podman run --rm --platform linux/amd64 fedora uname -m` | `x86_64` |
| T5 | UBI10 + dnf | `podman run --rm --platform linux/amd64 registry.access.redhat.com/ubi10/ubi dnf --version` | Version shown |

```bash
# T3: Run 5 sequential containers
for i in 1 2 3 4 5; do
  podman run --rm --platform linux/amd64 alpine uname -m
done
```

### 🟡 Real-World Tests (recommended, ~15 min)

| # | Test | Command | Check |
|---|------|---------|-------|
| T6 | dnf install | `podman run --rm --platform linux/amd64 fedora dnf install -y git` | Exits 0 |
| T7 | Python pip | `podman run --rm --platform linux/amd64 python:3.11-slim pip install requests` | Exits 0 |
| T8 | Node.js | `podman run --rm --platform linux/amd64 node:20-slim node -e "console.log('hello')"` | `hello` |
| T9 | podman build | See below | Build succeeds |
| T10 | rustc | `podman run --rm --platform linux/amd64 rust:latest rustc --version` | Version shown |

```bash
# T9: Build an x86_64 image
cat << 'EOF' > /tmp/Containerfile.test
FROM --platform=linux/amd64 alpine:latest
RUN apk add --no-cache curl && curl --version
EOF
podman build --platform linux/amd64 -f /tmp/Containerfile.test /tmp/
```

### 🔴 Stress Tests (optional, ~30 min)

| # | Test | Command | Check |
|---|------|---------|-------|
| T11 | Heavy build | `podman run --rm --platform linux/amd64 fedora bash -c 'dnf install -y gcc make && echo done'` | `done` |
| T12 | Long loop | `podman run --rm --platform linux/amd64 alpine sh -c 'for i in $(seq 1 100); do echo $i; done'` | `100` |
| T13 | Multi-distro | See below | All succeed |

```bash
# T13: Multiple distro test
podman run --rm --platform linux/amd64 alpine uname -m
podman run --rm --platform linux/amd64 fedora uname -m
podman run --rm --platform linux/amd64 ubuntu uname -m
podman run --rm --platform linux/amd64 registry.access.redhat.com/ubi10/ubi-micro uname -m
```

---

## Verified Results

Tested on MacBook Pro M1 Max, macOS 15.x, Podman 5.8.

### Code Cache Warmup (single container, 5 iterations)

| Workload | Run 1 | Run 5 | Speedup |
|----------|------:|------:|:-------:|
| Fedora `dnf check-update` | 19.2s | 1.3s | **13.8x** |
| Python `pip install pyarrow` | 15.2s | 5.6s | **2.7x** |
| `rustc --version` | 2.6s | 0.7s | **3.7x** |
| Arch Linux `pacman -Sy` | 1.2s | 0.1s | **12.7x** |

### Startup Latency

| Mode | Latency |
|------|--------:|
| Native ARM64 | ~2.1s |
| FEX-Emu x86_64 | ~2.4s |

---

## Known Limitations

| Case | Reason | Workaround |
|------|--------|------------|
| **AVX/AVX2 instructions** | FEX-Emu does not support AVX | Use SSE2-compatible builds |
| **MSSQL Server** | Requires AVX + runtime crash | Use native x86_64 host |
| **Go 1.24+ crypto** | `crypto/internal/fips140` SIGSEGV | Use Go ≤1.23 |
| **`applehv` provider** | Requires `libkrun` | Set provider to `libkrun` |

### Performance Notes

- **First run**: JIT compilation adds a few seconds of overhead
- **Repeated runs in same container**: Code cache approaches native speed
- **After container recreation**: Cache is ephemeral (per-container lifetime), JIT recompiles

---

## Architecture

```
macOS (Apple Silicon)
└── libkrun VM (Fedora CoreOS, aarch64)
    ├── FEX-Emu
    │   ├── FEXInterpreter (static-pie, binfmt_misc POCF)
    │   ├── FEXServer (per-container lifecycle)
    │   └── x86_64 RootFS (EROFS loop mount, 1.8GB)
    ├── OCI precreate hook
    │   └── amd64 annotation filter → FEX bind mounts
    ├── TSO kernel (6.19.10 + Asahi patches)
    │   └── PR_SET_MEM_MODEL / PR_GET_MEM_MODEL prctl
    └── QEMU-user-static
        └── s390x, ppc64le, riscv64 multi-arch support
```

### Image Components

| Component | Version |
|-----------|---------|
| Guest OS | Fedora CoreOS (aarch64) |
| Kernel | `6.19.10-200.tso.fc43.aarch64` (Asahi TSO patches) |
| FEX-Emu | #FEX-2603 (static-pie, 4 bug fix patches + log suppression) |
| Podman (in VM) | v5.8 stock RPM + OCI hook patch |
| SELinux | Enforcing |

---

## Related Repositories

All changes are on the `fex-emu` branch:

| Repository | Changes |
|------------|---------|
| [tnk4on/podman-machine-os](https://github.com/tnk4on/podman-machine-os/tree/fex-emu) | Machine OS image (Containerfile, activation script, OCI hook) |
| [tnk4on/FEX](https://github.com/tnk4on/FEX/tree/fex-emu) | Container support patches (VSOCK fallback, code cache path) |
| [tnk4on/podman](https://github.com/tnk4on/podman/tree/fex-emu) | OCI hook annotation injection, code cache SSH config |
| [tnk4on/libkrun](https://github.com/tnk4on/libkrun/tree/fex-emu) | Hardware TSO support (ACTLR_EL1) |
| [tnk4on/common](https://github.com/tnk4on/common/tree/fex-emu) | containers.conf FEXCodeCache setting |
| [tnk4on/krunkit](https://github.com/tnk4on/krunkit/tree/fex-emu) | VSOCK listen/connect, timesync |

---

## Feedback

### Collect environment info

```bash
echo "=== Environment ==="
echo "macOS: $(sw_vers -productVersion)"
echo "Chip: $(sysctl -n machdep.cpu.brand_string)"
echo "Podman: $(podman --version)"
echo "Provider: $(podman machine info --format '{{.Host.DefaultMachineProvider}}')"
```

### Report template

```
## Environment
- macOS:
- Chip (M1/M2/M3/M4):
- Podman version:
- Provider:

## Test Results
| Test | Result | Notes |
|------|:------:|-------|
| T1 x86_64 | | |
| T2 ARM64 | | |
| T3 Stability 5x | | |
| T4 Fedora | | |
| T5 UBI10+dnf | | |
| T6 dnf install | | |
| T7 Python pip | | |
| T8 Node.js | | |
| T9 podman build | | |
| T10 rustc | | |

## Issues (if any)
- Command:
- Error message:
- Steps to reproduce:
```

---

## Cleanup

Remove the FEX-Emu machine and restore your default setup:

```bash
# Option A: If you used the default machine
podman machine rm -f
podman machine init --now  # Recreates with official image

# Option B: If you used a named machine
podman machine rm -f fex
```

The FEX-Emu image makes no persistent changes to your macOS environment. Removing the machine fully restores the original state.

---

## License

This project integrates multiple open-source components. See individual repositories for their respective licenses.
