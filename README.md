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
| **JIT Code Cache** | Up to **30x speedup** on repeated runs (pure JIT effect); startup of Python, Perl, Ruby, GCC, and more is dramatically accelerated |
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

We provide two test scripts: `test.sh` for basic verification and real-world workloads, and `test-env.sh` for environment variable behavior.

### Run the test scripts

```bash
git clone https://github.com/tnk4on/podman-fex.git
cd podman-fex

# Full test suite (T1-T13)
./test.sh

# Quick mode — basic tests only (T1-T4)
./test.sh --quick

# Environment variable tests (E1-E15)
./test-env.sh

# With a named connection
./test.sh --connection fex
./test-env.sh --connection fex
```

The scripts report results and write detailed logs to `$TMPDIR`.

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

### 🟣 Environment Variable Tests (`test-env.sh`, ~3 min)

| # | Test | Verifies |
|---|------|----------|
| E1 | Code cache enabled + files generated | `FEX_ENABLECODECACHINGWIP=1` AND cache files exist |
| E2 | Code cache disabled | `-e FEX_ENABLECODECACHINGWIP=0` overrides default |
| E3 | Verbose cache pipeline (2-run) | 2nd run shows "Compiling code..." / "populated cache" |
| E4 | No verbose cache (control) | Without `FEX_VERBOSE_CACHE`, no pipeline detail |
| E5 | TSO enabled (env=true) | `FEX_TSOENABLED=true` accepted by FEX |
| E6 | TSO disabled (env=false) | `FEX_TSOENABLED=false` accepted, execution succeeds |
| E7 | FEX log visible | `FEX_SILENTLOG=false` + `FEX_OUTPUTLOG=stderr` shows debug |
| E8 | Default log silent | Default behavior: clean output, no debug lines |
| E9 | Multiblock JIT enabled | `FEX_MULTIBLOCK=true` accepted by FEX |
| E10 | Multiblock JIT disabled | `FEX_MULTIBLOCK=false` accepted, execution succeeds |
| E11 | OCI hook: DATA_LOCATION | OCI hook injects `FEX_APP_DATA_LOCATION` |
| E12 | OCI hook: CONFIG_LOCATION | OCI hook injects `FEX_APP_CONFIG_LOCATION` |
| E13 | OCI hook: CACHE_LOCATION | OCI hook injects `FEX_APP_CACHE_LOCATION` |
| E14 | All env sources combined | Hook + containers.conf + user `-e` coexist correctly |
| E15 | ARM64 isolation | FEX env vars not present in ARM64 containers |

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

When running repeated commands within the same container, JIT code cache accumulates and reduces execution time. The table below shows pure JIT cache effect — application-level caches (dnf metadata, pacman sync DB, etc.) are excluded where noted:

| Workload | Image | Run 1 | Run 4/5 | Speedup | Category |
|----------|-------|------:|--------:|:-------:|----------|
| `python3 -c 'print(42)'` | python:3.12 | 3,371ms | 111ms | **30.4x** | Interpreter startup |
| `g++ --version` | gcc:14-bookworm | 1,328ms | 45ms | **29.5x** | Compiler startup |
| `perl -e 'print 42'` | perl:5 | 1,042ms | 47ms | **22.2x** | Interpreter startup |
| `dpkg -l \| wc -l` | ubuntu:24.04 | 1,280ms | 69ms | **18.6x** | Package manager |
| `rpm -V bash` | fedora:42 | 2,331ms | 141ms | **16.5x** | Package verification |
| `ruby -e 'puts 42'` | ruby:3.3 | 3,271ms | 203ms | **16.1x** | Interpreter startup |
| `grep --version` | fedora:42 | 818ms | 53ms | **15.4x** | CLI tool | 
| `python3 -c 'print(42)'` | fedora:42 | 1,248ms | 91ms | **13.7x** | Interpreter startup |
| `go vet` | golang:1.23 | 1,022ms | 76ms | **13.4x** | Go toolchain |
| `psql --version` | debian:bookworm | 2,632ms | 203ms | **13.0x** | DB client |
| `pacman -Sy` | archlinux | 1,305ms | 105ms | **12.4x** | Package manager (sync DB cleared) |
| `file /usr/bin/bash` | fedora:42 | 530ms | 46ms | **11.5x** | CLI tool |
| `rpm -qa \| wc -l` | fedora:42 | 2,358ms | 210ms | **11.2x** | Package query |
| `git --version` | fedora:42 | 512ms | 46ms | **11.1x** | Version control |
| `go env GOROOT` | golang:1.23 | 675ms | 62ms | **10.9x** | Go toolchain |
| `cmake configure` | gcc:14 | 19,903ms | 2,081ms | **9.6x** | Build system |
| `django-admin --version` | python:3.12 | 3,981ms | 439ms | **9.1x** | Python framework |
| `cmake --version` | fedora:42 | 683ms | 81ms | **8.4x** | Build system |
| `php -r 'echo 42'` | php:8.3 | 2,085ms | 248ms | **8.4x** | Interpreter startup |
| `bash --version` | fedora:42 | 321ms | 40ms | **8.0x** | Shell |
| `perl regex (10k)` | perl:5 | 479ms | 62ms | **7.7x** | Regex processing |
| `cargo --version` | rust:1.83 | 1,163ms | 153ms | **7.6x** | Rust toolchain |
| `g++ -O2 hello.cpp` (STL) | gcc:14 | 13,385ms | 1,781ms | **7.5x** | C++ compilation |
| `yum --version` | ubi9 | 2,769ms | 399ms | **6.9x** | Package manager |
| `g++ -O2 hello.cpp` | gcc:14 | 8,805ms | 1,321ms | **6.7x** | C++ compilation |
| `ruff --version` | python:3.12 | 355ms | 59ms | **6.0x** | Linter (Rust binary) |
| `dnf --version` | fedora:42 | 1,062ms | 188ms | **5.7x** | Package manager |
| `ansible --version` | python:3.12 | 4,642ms | 977ms | **4.8x** | DevOps tool |
| `gcc hello.c -o hello` | gcc:14 | 3,570ms | 761ms | **4.7x** | C compilation |
| `valgrind --version` | debian:bookworm | 314ms | 77ms | **4.1x** | Debug tool |
| `rustc --version` | rust:1.83 | 2,319ms | 668ms | **3.5x** | Rust compiler |
| `mypy --version` | python:3.12 | 1,993ms | 566ms | **3.5x** | Type checker |

FEX-Emu writes JIT-compiled code to the cache **asynchronously** — the compiled results from Run N are flushed to disk in the background and become available from Run N+1 onward. This means:

- **Run 1**: Full JIT compilation (slowest)
- **Run 2**: Cache from Run 1 is still being written; may actually be **slower** than Run 1
- **Run 3+**: Cache is fully populated; execution approaches near-native speed

> **Note**: JVM-based runtimes (Java, Kotlin), .NET, and Node.js show minimal cache benefit because their own JIT compilers (HotSpot, CoreCLR, V8) create a "JIT-on-JIT" overhead that dominates execution time.

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
| `FEX_VERBOSE_CACHE` | `0` / `1` | unset (off) | Show cache pipeline detail (requires `FEX_SILENTLOG=false` + `FEX_OUTPUTLOG=stderr`, visible on 2nd+ run) |
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

**Enable verbose cache logging** (shows cache pipeline on 2nd+ run):

```bash
# Create a named container with verbose cache
podman run --name test-cache --platform linux/amd64 \
  -e FEX_VERBOSE_CACHE=1 -e FEX_SILENTLOG=false -e FEX_OUTPUTLOG=stderr \
  alpine sh -c "echo hello"

# Run it again — 2nd run shows "Compiling code..." / "populated cache"
podman start -a test-cache

# Clean up
podman rm test-cache
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

The JIT code cache is enabled by default in the machine image. The `fex-activation.sh` service writes `FEX_ENABLECODECACHINGWIP=1` to the VM's `containers.conf` at first boot.

> **Why the machine image sets this default:** Podman's `[machine] fex_code_cache` setting and `fexenv.ApplyFEXCodeCache()` are only available in the project's custom Podman build — package Podman (`brew install podman`) does not have them. By configuring the default inside the machine image, users can use standard Podman as-is without any host-side patches.

To disable it manually:

```bash
# Rootless
podman machine ssh -- 'sed -i "s/env = .*/env = []/" ~/.config/containers/containers.conf'
# Rootful
podman machine ssh -- 'sudo sed -i "s/env = .*/env = []/" /root/.config/containers/containers.conf'
```

To re-enable:

```bash
# Rootless
podman machine ssh -- 'sed -i "s/env = .*/env = [\"FEX_ENABLECODECACHINGWIP=1\"]/" ~/.config/containers/containers.conf'
# Rootful
podman machine ssh -- 'sudo sed -i "s/env = .*/env = [\"FEX_ENABLECODECACHINGWIP=1\"]/" /root/.config/containers/containers.conf'
```

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
