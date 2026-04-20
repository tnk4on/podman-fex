# FEX-Emu for Podman Machine

> **Preview Release** — April 2026
> **Image**: `quay.io/tnk4on/machine-os:5.8` or `quay.io/tnk4on/machine-os:6.0`

Run x86_64 Linux containers on Apple Silicon Macs at near-native speed using [FEX-Emu](https://github.com/FEX-Emu/FEX) JIT emulation inside [Podman Machine](https://docs.podman.io/en/latest/markdown/podman-machine.1.html) (libkrun backend).

> [!CAUTION]
> This is a **personal project** and is not an official Podman product. The provided image comes with **no warranty or support guarantees**. Use at your own risk.

## Background

Running x86_64 containers on Apple Silicon with Podman has long been problematic. QEMU user-mode is slow and crashes often, and Rosetta 2 integration with libkrun is not viable (see [investigation report](https://tnk4on.github.io/libkrun-rosetta/) for details). This project replaces both with **FEX-Emu**, a JIT-based x86_64 emulator [officially adopted by Fedora 42](https://fedoraproject.org/wiki/Changes/FEX).

| Feature | Description |
|---------|-------------|
| **JIT Code Cache** | Up to **30x speedup** on repeated runs (pure JIT effect); startup of Python, Perl, Ruby, GCC, and more is dramatically accelerated |
| **OCI Hook Integration** | FEX mounts only into x86_64 containers; ARM64 has zero overhead |
| **SELinux Enforcing** | Runs with security policies fully enabled |
| **QEMU Fallback** | x86/x86_64 QEMU binaries are pre-installed; FEX can be [disabled](#disabling-fex-qemu-fallback) to fall back to QEMU |

### Community-Reported Issues Fixed

We tested against **17 known x86_64 emulation issues** reported in the Podman community — problems that occur with QEMU or Rosetta on Apple Silicon. FEX-Emu resolves **13 of 17** (76.5%):

| Category | Tests | Passed | Rate |
|----------|:-----:|:------:|:----:|
| QEMU SIGSEGV | 5 | 5 | **100%** |
| Hang / Freeze | 5 | 5 | **100%** |
| Build Failures | 5 | 2 | 40% |
| Rosetta Crash | 1 | 0 | 0% |
| Behavioral | 1 | 1 | **100%** |
| **Total** | **17** | **13** | **76.5%** |

See [TEST-RESULTS.md](docs/TEST-RESULTS.md) for per-issue details, reproduction commands, and full terminal output.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Hardware** | Apple Silicon Mac |
| **macOS** | Podman supported version (tested on macOS 26.4.1) |
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

# Create FEX-Emu machine (use :5.8 for Podman 5.x, :6.0 for Podman 6.x)
podman machine init \
  --image docker://quay.io/tnk4on/machine-os:5.8 --now
```

### Option B: Side-by-Side (keep existing machine)

```bash
# Create a separate machine named "fex" (use :5.8 for Podman 5.x, :6.0 for Podman 6.x)
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

### Disabling FEX (QEMU Fallback)

FEX-Emu is enabled by default. To disable it and fall back to QEMU for x86_64 emulation, create a marker file inside the VM and restart:

```bash
# Disable FEX → QEMU fallback
podman machine ssh -- "sudo touch /etc/containers/disable-fex-emu"
podman machine stop && podman machine start

# Re-enable FEX
podman machine ssh -- "sudo rm /etc/containers/disable-fex-emu"
podman machine stop && podman machine start
```

To verify which emulator is active:

```bash
# Check binfmt handler for x86_64
podman machine ssh -- "ls /proc/sys/fs/binfmt_misc/ | grep -E 'FEX|qemu'"
# FEX enabled:  FEX-x86  FEX-x86_64  qemu-aarch64_be
# FEX disabled: qemu-aarch64_be  qemu-i386  qemu-i486  qemu-x86_64
```

> [!NOTE]
> When upstream Podman merges FEX support, this will be controllable via `containers.conf`:
> ```toml
> [machine]
> fex_emu = false
> ```
> The marker file mechanism remains as the guest-side SSOT, but Podman will manage it automatically on `podman machine start`. See [docs/FEX-QEMU-SWITCHING.md](docs/FEX-QEMU-SWITCHING.md) for the full architecture.

---

## Testing

We provide a unified test framework in `tests/` and benchmark tools in `bench/`.

### Directory Structure

```
tests/
├── test-fex.sh          # Unified runner (61 tests, 7 categories)
├── lib-test.sh          # Shared library
├── run/                 # Issue reproduction scripts (13)
├── build/               # Build test contexts (5)
└── results/             # Test output logs

bench/
├── compare.sh           # Cross-backend comparison (20 workloads)
├── cache-warmup.sh      # JIT warmup measurement (7 workloads)
├── cache-persistent.sh  # Persistent container cache (7 workloads)
└── results/             # Benchmark output

docs/                    # Documentation
```

### Run the test suite

```bash
git clone https://github.com/tnk4on/podman-fex.git
cd podman-fex

# All 61 tests (7 categories: infra/basic/hook/env/issue/workload/stress)
bash tests/test-fex.sh --connection test

# Specific category
bash tests/test-fex.sh --connection test --category basic

# Specific tests
bash tests/test-fex.sh --connection test --test I16,B01

# List all tests
bash tests/test-fex.sh --list

# With a named connection
bash tests/test-fex.sh --connection fex
```

The script reports results and writes detailed logs to `tests/results/`.

### 🟢 Basic Tests (~2 min)

| ID | Test | Expected |
|---|------|----------|
| B01 | x86_64 container (`alpine uname -m`) | `x86_64` |
| B02 | ARM64 regression (`alpine uname -m`) | `aarch64` |
| B03 | Stability — 5 sequential x86_64 containers | All `x86_64` |
| B04 | Multi-distro (Fedora, Ubuntu, UBI10) | All `x86_64` |

### 🟡 Issue Reproduction Tests (~5 min)

All 17 [community-reported issues](#community-reported-issues-fixed) are verified by the script:

| ID | Test | Issue |
|---|------|-------|
| I01 | gawk SIGSEGV | [#23219](https://github.com/containers/podman/issues/23219) |
| I02 | SWC/Next.js SIGILL | [#23269](https://github.com/containers/podman/issues/23269) |
| I03 | sudo BuildKit | [#24647](https://github.com/containers/podman/issues/24647) |
| I04 | Angular/Node build | [#25272](https://github.com/containers/podman/issues/25272) |
| I05 | PyArrow SIGSEGV | [#26036](https://github.com/containers/podman/issues/26036) |
| I06 | Express freeze | [#26572](https://github.com/containers/podman/issues/26572) |
| I07 | su -l login shell | [#26656](https://github.com/containers/podman/issues/26656) |
| I08 | Go hello build | [#26881](https://github.com/containers/podman/issues/26881) |
| I09 | Go godump build | [#26919](https://github.com/containers/podman/issues/26919) |
| I10 | MSSQL 2022 SIGSEGV | [#27078](https://github.com/containers/podman/issues/27078) |
| I11 | Arch Linux hang | [#27210](https://github.com/containers/podman/issues/27210) |
| I12 | jemalloc SIGSEGV | [#27320](https://github.com/containers/podman/issues/27320) |
| I13 | redis-cluster SIGSEGV | [D#27601](https://github.com/containers/podman/discussions/27601) |
| I14 | Ubuntu hang | [#27799](https://github.com/containers/podman/issues/27799) |
| I15 | Fedora hang | [#27817](https://github.com/containers/podman/issues/27817) |
| I16 | rustc SIGSEGV | [#28169](https://github.com/containers/podman/issues/28169) |
| I17 | MSSQL 2025 AVX | [#28184](https://github.com/containers/podman/issues/28184) |

Known failures (XFAIL): I04, I08, I09, I10, I17 — see [Known Limitations](#known-limitations).

For detailed reproduction logs, see [docs/TEST-RESULTS.md](docs/TEST-RESULTS.md).

### 🔵 Workload Tests (~5 min)

| ID | Test | Expected |
|---|------|----------|
| W01 | `dnf install -y git` on Fedora x86_64 | Exit 0 |
| W02 | `podman build` an x86_64 image | Build succeeds |

### 🟣 Environment Variable Tests (`tests/test-fex.sh --category env`, ~3 min)

| ID | Test | Verifies |
|---|------|----------|
| E01 | Code cache enabled + files generated | `FEX_ENABLECODECACHINGWIP=1` AND cache files exist |
| E02 | Code cache disabled | `-e FEX_ENABLECODECACHINGWIP=0` overrides default |
| E03 | Verbose cache pipeline (2-run) | 2nd run shows "Compiling code..." / "populated cache" |
| E04 | No verbose cache (control) | Without `FEX_VERBOSE_CACHE`, no pipeline detail |
| E07 | FEX log visible | `FEX_SILENTLOG=false` + `FEX_OUTPUTLOG=stderr` shows debug |
| E08 | Default log silent | Default behavior: clean output, no debug lines |
| E11 | OCI hook: DATA_LOCATION | containers.conf injects `FEX_APP_DATA_LOCATION` |
| E12 | OCI hook: CONFIG_LOCATION | containers.conf injects `FEX_APP_CONFIG_LOCATION` |
| E13 | OCI hook: CACHE_LOCATION | containers.conf injects `FEX_APP_CACHE_LOCATION` |
| E14 | All env sources combined | containers.conf + drop-in + user `-e` coexist correctly |
| E15 | ARM64 isolation | No FEX bind mounts in ARM64 containers |

---

## Performance

Tested on MacBook Pro M1 Max, macOS 26.4.1, Podman 5.8.

### Startup Latency

FEX-Emu adds minimal overhead to container startup compared to native ARM64:

| Mode | `podman run --rm alpine echo hello` | Notes |
|------|:-----------------------------------:|-------|
| Native ARM64 | ~2.1s | Baseline |
| FEX-Emu x86_64 (cold) | ~2.8s | First run, JIT compilation |
| FEX-Emu x86_64 (warm) | ~2.4s | With code cache populated |

The ~0.3s overhead on warm runs comes from FEX-Emu initialization (FEXServer startup, RootFS access, binfmt_misc dispatch).

### Code Cache Warmup (single container, 5 iterations)

When running repeated commands within the same container, JIT code cache accumulates and reduces execution time (Top 5 — [full results](docs/BENCHMARK.md)):

| Workload | Image | Run 1 | Run 4/5 | Speedup |
|----------|-------|------:|--------:|:-------:|
| `python3 -c 'print(42)'` | python:3.12 | 3,371ms | 111ms | **30.4x** |
| `g++ --version` | gcc:14-bookworm | 1,328ms | 45ms | **29.5x** |
| `perl -e 'print 42'` | perl:5 | 1,042ms | 47ms | **22.2x** |
| `dpkg -l \| wc -l` | ubuntu:24.04 | 1,280ms | 69ms | **18.6x** |
| `rpm -V bash` | fedora:42 | 2,331ms | 141ms | **16.5x** |

> Code cache is **ephemeral** (per-container lifetime). When a container is removed, the cache is lost and JIT recompilation occurs on the next run. See [BENCHMARK.md](docs/BENCHMARK.md) for methodology, 32 workloads, and runtimes with no cache benefit.

---

## Known Limitations

| Case | Reason | Workaround |
|------|--------|------------|
| **MSSQL Server** | Runtime crash (root cause under investigation) | Use native x86_64 host |
| **Go 1.24+ crypto** | `crypto/internal/fips140` SIGSEGV | Use Go 1.23 or earlier |
| **Angular/Node (esbuild)** | esbuild (Go) SIGSEGV | Same root cause as Go crypto |
| **`applehv` provider** | Requires `libkrun` | Set provider to `libkrun` |

---

## Environment Variables

FEX-Emu behavior can be tuned via environment variables passed with `podman run -e`. Some variables are set automatically by the system; others are available for manual use.

### Automatically Set

These are injected by `containers.conf` or its drop-in — you normally don't need to set them yourself:

| Variable | Default | Set By | Purpose |
|----------|---------|--------|---------|
| `FEX_APP_DATA_LOCATION` | `/tmp/fex-emu/` | containers.conf | FEX data directory (writable for any user) |
| `FEX_APP_CONFIG_LOCATION` | `/tmp/fex-emu/` | containers.conf | FEX config lookup directory |
| `FEX_APP_CACHE_LOCATION` | `/tmp/fex-emu/cache/` | containers.conf | JIT code cache storage directory |
| `FEX_ENABLECODECACHINGWIP` | `1` | containers.conf | Enable JIT code cache for repeated runs |

### User-Configurable

Pass these with `-e` to override defaults or enable additional features:

| Variable | Values | Default | Purpose |
|----------|--------|---------|---------|
| `FEX_ENABLECODECACHINGWIP` | `0` / `1` | `1` | Disable (`0`) or enable (`1`) the JIT code cache |
| `FEX_VERBOSE_CACHE` | `0` / `1` | unset (off) | Show cache pipeline detail (requires `FEX_SILENTLOG=false` + `FEX_OUTPUTLOG=stderr`, visible on 2nd+ run) |
| `FEX_SILENTLOG` | `false` / `true` | `true` | Suppress FEX internal log output |
| `FEX_OUTPUTLOG` | `stderr` / `server` / file | `server` | Redirect FEX log output destination |

> **Other FEX variables** (not used in this project's tests): `FEX_MULTIBLOCK` (multi-block JIT, default: `true`), `FEX_ROOTFS` (override RootFS path, auto-configured by OCI hook), `FEX_GDBSERVER` (GDB server for x86_64 debugging). See [FEX-Emu documentation](https://github.com/FEX-Emu/FEX) for details.

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

**Show FEX logs on stderr** (for troubleshooting):

```bash
podman run --rm --platform linux/amd64 \
  -e FEX_SILENTLOG=false -e FEX_OUTPUTLOG=stderr alpine uname -m
```

### Host-Side Configuration

The JIT code cache is enabled by default in the machine image. The `fex-activation.sh` service configures it at first boot.

> **Why the machine image sets this default:** Podman's `[machine] fex_code_cache` setting and `fexenv.ApplyFEXCodeCache()` are only available in the project's custom Podman build — package Podman (`brew install podman`) does not have them. By configuring the default inside the machine image, users can use standard Podman as-is without any host-side patches.

The configuration is in the base `containers.conf`:
- `FEX_APP_*` env variables (data/config/cache paths)
- `FEX_ENABLECODECACHINGWIP=1` (code cache enabled)

To toggle code caching, use a `containers.conf.d/` drop-in override. Podman's env→map conversion means later values in the array win, so `{append=true}` with `=0` overrides the base `=1`.

**Disable code cache:**

```bash
# Rootless
podman machine ssh -- 'mkdir -p ~/.config/containers/containers.conf.d && printf "[containers]\nenv = [\"FEX_ENABLECODECACHINGWIP=0\", {append=true}]\n" > ~/.config/containers/containers.conf.d/fex-code-cache.conf'
# Rootful
podman machine ssh -- 'sudo mkdir -p /root/.config/containers/containers.conf.d && printf "[containers]\nenv = [\"FEX_ENABLECODECACHINGWIP=0\", {append=true}]\n" | sudo tee /root/.config/containers/containers.conf.d/fex-code-cache.conf'
```

**Re-enable code cache** (remove the override — base `=1` applies):

```bash
# Rootless
podman machine ssh -- 'rm -f ~/.config/containers/containers.conf.d/fex-code-cache.conf'
# Rootful
podman machine ssh -- 'sudo rm -f /root/.config/containers/containers.conf.d/fex-code-cache.conf'
```

### Persistent Drop-In for Other FEX Variables

The same `containers.conf.d/` + `{append=true}` mechanism works for any FEX environment variable — not just `FEX_ENABLECODECACHINGWIP`. Later values in the env array override earlier ones for the same key.

**Example: Enable verbose cache logging + FEX debug output permanently:**

```bash
podman machine ssh -- 'mkdir -p ~/.config/containers/containers.conf.d && printf "[containers]\nenv = [\"FEX_VERBOSE_CACHE=1\", \"FEX_SILENTLOG=false\", \"FEX_OUTPUTLOG=stderr\", {append=true}]\n" > ~/.config/containers/containers.conf.d/fex-tuning.conf'
```

**Example: Override cache path:**

```bash
podman machine ssh -- 'mkdir -p ~/.config/containers/containers.conf.d && printf "[containers]\nenv = [\"FEX_APP_CACHE_LOCATION=/tmp/my-cache/\", {append=true}]\n" > ~/.config/containers/containers.conf.d/fex-cache-path.conf'
```

To revert, simply remove the drop-in file — the base `containers.conf` values are restored.

Multiple drop-in files are loaded in alphabetical order by filename.

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
    ├── containers.conf
    │   ├── FEX_APP_* env (data/config/cache paths)
    │   └── FEX_ENABLECODECACHINGWIP=1 (code cache default)
    └── QEMU-user-static
        └── x86, aarch64_be (pre-installed; s390x etc. require extra packages)
```

### Image Components

| Component | Version |
|-----------|---------|
| Guest OS | Fedora CoreOS (aarch64) |
| Kernel | `6.19.10-200.fc43.aarch64` |
| FEX-Emu | FEX-2604 base (static-pie, 4 container patches) |
| Podman (in VM) | v5.8 stock RPM + OCI hook patch |
| SELinux | Enforcing |

---

## Source Code

The published image is built from the `fex-emu` branch of each repository below. All source code is available for review:

| Repository | Changes |
|------------|---------|
| [tnk4on/podman-machine-os](https://github.com/tnk4on/podman-machine-os/tree/fex-emu) | Machine OS image (Containerfile, activation script, OCI hook) |
| [tnk4on/FEX](https://github.com/tnk4on/FEX/tree/fex-emu) | Container support (VSOCK fallback, code cache path, container detection) |
| [tnk4on/podman](https://github.com/tnk4on/podman/tree/fex-emu) | OCI hook annotation injection, code cache drop-in management |
| [tnk4on/buildah](https://github.com/tnk4on/buildah/tree/fex-emu) | Rootless OCI hook support for `podman build` |
| [tnk4on/container-libs](https://github.com/tnk4on/container-libs/tree/fex-emu) | FEX containers.conf settings definition (common/) |

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

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

This project integrates multiple open-source components. See individual repositories for their respective licenses.
