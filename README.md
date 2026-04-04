# FEX-Emu for Podman Machine

> **Preview Release** — April 2026
> **Image**: `quay.io/tnk4on/machine-os:5.8`

Run x86_64 Linux containers on Apple Silicon Macs at near-native speed using [FEX-Emu](https://github.com/FEX-Emu/FEX) JIT emulation inside [Podman Machine](https://docs.podman.io/en/latest/markdown/podman-machine.1.html) (libkrun backend).

> [!CAUTION]
> This is a **personal project** and is not an official Podman product. The provided image comes with **no warranty or support guarantees**. Use at your own risk.

## Background

Running x86_64 containers on Apple Silicon with Podman has long been problematic. QEMU user-mode is slow and crashes often, and Rosetta 2 integration with libkrun is not viable (see [investigation report](https://tnk4on.github.io/libkrun-rosetta/) for details). This project replaces both with **FEX-Emu**, a JIT-based x86_64 emulator [officially adopted by Fedora 42](https://fedoraproject.org/wiki/Changes/FEX).

| Feature | Description |
|---------|-------------|
| **JIT Code Cache** | Up to **13.8x speedup** on repeated runs within the same container |
| **Hardware TSO** | Leverages Apple Silicon's TSO mode for x86 memory model emulation |
| **OCI Hook Integration** | FEX mounts only into x86_64 containers; ARM64 has zero overhead |
| **SELinux Enforcing** | Runs with security policies fully enabled |
| **Non-x86 via QEMU** | Architectures other than x86/x86_64 (s390x, ppc64le, riscv64, etc.) are handled by QEMU-user-static |

### Community-Reported Issues Fixed

We tested against **17 known x86_64 emulation issues** reported in the Podman community — problems that occur with QEMU or Rosetta on Apple Silicon. FEX-Emu resolves **12 of 17** (70.6%):

| Category | Tests | Passed | Rate |
|----------|:-----:|:------:|:----:|
| QEMU SIGSEGV | 5 | 5 | **100%** |
| Hang / Freeze | 5 | 5 | **100%** |
| Build Failures | 5 | 1 | 20% |
| Rosetta Crash | 1 | 0 | 0% |
| Behavioral | 1 | 1 | **100%** |
| **Total** | **17** | **12** | **70.6%** |

See [TEST-RESULTS.md](TEST-RESULTS.md) for per-issue details, reproduction commands, and full terminal output.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Hardware** | Apple Silicon Mac |
| **macOS** | Podman supported version (tested on macOS 26.3.1) |
| **Podman** | v5.8+ (`brew install podman` or [official PKG](https://podman.io/)) |
| **Provider** | `libkrun` (see below) |

### Set the provider to libkrun

The `libkrun` provider is **not** the default in Podman 5.8. You must set it explicitly:

```bash
mkdir -p ~/.config/containers
cat >> ~/.config/containers/containers.conf << 'EOF'
[machine]
provider = "libkrun"
EOF
```

Verify:

```bash
podman machine info --format '{{.Host.DefaultMachineProvider}}'
# Must show: libkrun
```

> [!IMPORTANT]
> This image requires the **`libkrun`** provider. It does **not** work with Apple Virtualization.framework (`applehv`).

---

## Quick Start

### Option A: Clean Install (replace existing machine)

> [!WARNING]
> This will **delete your existing default machine**, including all container images, volumes, and data stored inside it. Use Option B if you want to keep your current setup.

```bash
# Remove existing default machine
podman machine stop
podman machine rm -f

# Create FEX-Emu machine
podman machine init \
  --image docker://quay.io/tnk4on/machine-os:5.8 --now
```

### Option B: Side-by-Side (keep existing machine)

```bash
# Create a separate machine named "fex"
podman machine init fex \
  --image docker://quay.io/tnk4on/machine-os:5.8 --now

# Use --connection flag for all commands
podman --connection fex run --rm --platform linux/amd64 alpine uname -m
```

> [!TIP]
> For heavy build workloads, you can increase memory with `--memory 4096` or higher.

### Verify it works

```bash
# x86_64 container
podman run --rm --platform linux/amd64 alpine uname -m
# → x86_64

# ARM64 container (regression check)
podman run --rm --platform linux/arm64 alpine uname -m
# → aarch64
```

### Cleanup

To remove the FEX-Emu machine and restore your default setup:

```bash
# Option A: If you used the default machine
podman machine rm -f
podman machine init --now  # Recreates with official image

# Option B: If you used a named machine
podman machine rm -f fex
```

The FEX-Emu image makes no persistent changes to your macOS environment. Removing the machine fully restores the original state.

---

## Testing

We provide a test script that covers basic verification and real-world workloads.

### Run the test script

```bash
git clone https://github.com/tnk4on/podman-fex.git
cd podman-fex
./test.sh
```

The script runs the following tests and reports results:

### 🟢 Basic Tests (~2 min)

| # | Test | Expected |
|---|------|----------|
| T1 | x86_64 container (`alpine uname -m`) | `x86_64` |
| T2 | ARM64 regression (`alpine uname -m`) | `aarch64` |
| T3 | Stability — 5 sequential x86_64 containers | All `x86_64` |
| T4 | Multi-distro (Fedora, Ubuntu, UBI10) | All `x86_64` |

### 🟡 Issue Reproduction Tests (~5 min)

A subset of [community-reported issues](#community-reported-issues-fixed) verified by the script:

| # | Test | Issue |
|---|------|-------|
| T5 | rustc SIGSEGV | [#28169](https://github.com/containers/podman/issues/28169) |
| T6 | PyArrow SIGSEGV | [#26036](https://github.com/containers/podman/issues/26036) |
| T7 | Arch Linux hang | [#27210](https://github.com/containers/podman/issues/27210) |
| T8 | Fedora shell hang | [#27817](https://github.com/containers/podman/issues/27817) |
| T9 | Ubuntu 25.10 hang | [#27799](https://github.com/containers/podman/issues/27799) |
| T10 | Node.js build hang | [#25272](https://github.com/containers/podman/issues/25272) |
| T11 | sudo nosuid in build | [#24647](https://github.com/containers/podman/issues/24647) |

For the full 17-test suite with detailed reproduction logs, see [TEST-RESULTS.md](TEST-RESULTS.md).

### 🔵 Workload Tests (~5 min)

| # | Test | Expected |
|---|------|----------|
| T12 | `dnf install -y git` on Fedora x86_64 | Exit 0 |
| T13 | `podman build` an x86_64 image | Build succeeds |

---

## Performance

Tested on MacBook Pro M1 Max, macOS 26.3.1, Podman 5.8.

### Startup Latency

FEX-Emu adds minimal overhead to container startup compared to native ARM64:

| Mode | `podman run --rm alpine echo hello` | Notes |
|------|:-----------------------------------:|-------|
| Native ARM64 | ~2.1s | Baseline |
| FEX-Emu x86_64 (cold) | ~2.8s | First run, JIT compilation |
| FEX-Emu x86_64 (warm) | ~2.4s | With code cache populated |

The ~0.3s overhead on warm runs comes from FEX-Emu initialization (FEXServer startup, RootFS access, binfmt_misc dispatch).

### Code Cache Warmup (single container, 5 iterations)

When running repeated commands within the same container, JIT code cache accumulates and dramatically reduces execution time:

| Workload | Run 1 | Run 5 | Speedup |
|----------|------:|------:|:-------:|
| Fedora `dnf check-update` | 19.2s | 1.3s | **13.8x** |
| Python `pip install pyarrow` | 15.2s | 5.6s | **2.7x** |
| `rustc --version` | 2.6s | 0.7s | **3.7x** |
| Arch Linux `pacman -Sy` | 1.2s | 0.1s | **12.7x** |

FEX-Emu writes JIT-compiled code to the cache **asynchronously** — the compiled results from Run N are flushed to disk in the background and become available from Run N+1 onward. This means:

- **Run 1**: Full JIT compilation (slowest)
- **Run 2**: Cache from Run 1 is still being written; may not be faster yet
- **Run 3+**: Cache is fully populated; execution approaches near-native speed

> Code cache is **ephemeral** (per-container lifetime). When a container is removed, the cache is lost and JIT recompilation occurs on the next run.

---

## Known Limitations

| Case | Reason | Workaround |
|------|--------|------------|
| **AVX/AVX2 instructions** | FEX-Emu does not support AVX | Use SSE2-compatible builds |
| **MSSQL Server** | Requires AVX + runtime crash | Use native x86_64 host |
| **Go 1.24+ crypto** | `crypto/internal/fips140` SIGSEGV | Use Go ≤1.23 |
| **`applehv` provider** | Requires `libkrun` | Set provider to `libkrun` |

---

## Environment Variables

FEX-Emu behavior can be tuned via environment variables passed with `podman run -e`. Some variables are set automatically by the system; others are available for manual use.

### Automatically Set

These are injected by the OCI hook or `containers.conf` — you normally don't need to set them yourself:

| Variable | Default | Set By | Purpose |
|----------|---------|--------|---------|
| `FEX_ENABLECODECACHINGWIP` | `1` | containers.conf | Enable JIT code cache for repeated runs |
| `FEX_APP_DATA_LOCATION` | `/tmp/fex-data/` | OCI hook | FEX data directory (writable for any user) |
| `FEX_APP_CONFIG_LOCATION` | `/tmp/fex-data/` | OCI hook | FEX config lookup directory |
| `FEX_APP_CACHE_LOCATION` | `/tmp/fex-data/cache/` | OCI hook | JIT code cache storage directory |

### User-Configurable

Pass these with `-e` to override defaults or enable additional features:

| Variable | Values | Default | Purpose |
|----------|--------|---------|---------|
| `FEX_ENABLECODECACHINGWIP` | `0` / `1` | `1` | Disable (`0`) or enable (`1`) the JIT code cache |
| `FEX_VERBOSE_CACHE` | `0` / `1` | unset (off) | Show code cache hit/miss log messages on stderr |
| `FEX_TSOENABLED` | `false` / `true` | `true` | Toggle x86 Total Store Order memory model emulation |
| `FEX_SILENTLOG` | `false` / `true` | `true` | Suppress FEX internal log output |
| `FEX_OUTPUTLOG` | `stderr` / `server` / file | `server` | Redirect FEX log output destination |
| `FEX_MULTIBLOCK` | `false` / `true` | `true` | Enable multi-block JIT compilation |
| `FEX_ROOTFS` | path | (auto) | Override x86_64 RootFS path |
| `FEX_GDBSERVER` | `false` / `true` | `false` | Start a GDB server for debugging x86_64 code |

### Examples

**Disable code cache** (useful for debugging JIT issues):

```bash
podman run --rm --platform linux/amd64 \
  -e FEX_ENABLECODECACHINGWIP=0 alpine uname -m
```

**Enable verbose cache logging** (see cache hit/miss details):

```bash
podman run --rm --platform linux/amd64 \
  -e FEX_VERBOSE_CACHE=1 alpine sh -c "echo hello"
```

**Disable TSO emulation** (may improve performance for single-threaded workloads):

```bash
podman run --rm --platform linux/amd64 \
  -e FEX_TSOENABLED=false alpine uname -m
```

**Show FEX logs on stderr** (for troubleshooting):

```bash
podman run --rm --platform linux/amd64 \
  -e FEX_SILENTLOG=false -e FEX_OUTPUTLOG=stderr alpine uname -m
```

### Host-Side Configuration

The JIT code cache is controlled at the Podman Machine level via `containers.conf`:

```toml
# ~/.config/containers/containers.conf (macOS host)
[machine]
fex_code_cache = true   # default: true
```

When `fex_code_cache = false`, `podman machine start` will remove the `FEX_ENABLECODECACHINGWIP` setting from the VM, disabling code caching for all containers.

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

## Source Code

The published image is built from the `fex-emu` branch of each repository below. All source code is available for review:

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

Please report your results and any issues via [Podman Discussions](https://github.com/containers/podman/discussions).

Include the following information:

- macOS version (`sw_vers -productVersion`)
- Apple Silicon chip model
- Podman version (`podman --version`)
- Machine provider (`podman machine info --format '{{.Host.DefaultMachineProvider}}'`)
- Which tests passed / failed
- For failures: the exact command, full error output, and steps to reproduce

---

## License

This project integrates multiple open-source components. See individual repositories for their respective licenses.
