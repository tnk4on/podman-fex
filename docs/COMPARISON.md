# Cross-Backend Benchmark: FEX-Emu vs QEMU vs Rosetta

## Executive Summary

Comparison of x86_64 container emulation performance across 3 backends on Apple Silicon (M1 Max).
20 practical workloads in 7 categories, evaluated by min values.

| Backend | VM Provider | Emulation | Interpreter Startup | Package Mgr | Compilation |
|---------|-------------|-----------|:---:|:---:|:---:|
| **FEX-Emu** | libkrun | JIT | 14–99ms | 19–134ms | 181–1,345ms |
| **QEMU** | libkrun | qemu-user-static | 63–516ms | 76–608ms | 482–3,775ms |
| **Rosetta** | applehv | Binary translation | 54–225ms | 71–281ms | 316–1,322ms |

**Conclusions**:
- **FEX is faster than QEMU in 19/20 workloads** — dominant across all categories (rustc: QEMU crashes)
- **FEX vs Rosetta: 16 wins / 1 tie / 3 losses** — FEX decisively leads in interpreter startup, package manager, and compilation
- **Rosetta is faster in rustc / java / node** — AOT translation favors JIT runtimes
- **FEX is the only high-speed emulation option for libkrun** — Rosetta is exclusive to applehv

## Environment

| Item | Detail |
|------|--------|
| Host | Apple M1 Max, macOS 26.4.1 |
| Podman | 5.8.1 (`/opt/podman/bin/podman`) |
| FEX VM | libkrun, 4 CPU / 8 GiB, Fedora CoreOS + FEX-Emu (`quay.io/tnk4on/machine-os:5.8`) |
| FEX Build | FEX-2604, `-DCMAKE_BUILD_TYPE=Release`, static-pie |
| FEX Kernel | `6.19.10-200.fc43.aarch64` (standard, non-TSO) |
| QEMU VM | libkrun, 4 CPU / 8 GiB, Fedora CoreOS (default image, qemu-user-static) |
| Rosetta VM | applehv, 4 CPU / 8 GiB, Fedora CoreOS (default image, Rosetta binary translation) |
| Date | 2026-04-20 (FEX/QEMU), 2026-04-06 (Rosetta) |

> **Methodology**: Each workload is executed via `podman run --rm bash -c`. All backends run 10 iterations and the minimum value is taken. The OCI hook sets `FEX_APP_*` environment variables so the JIT code cache is active.

## Full Results

20 workloads × 3 backends. **min values** are used. **Winner** = fastest backend (Tie = ±10%).

### Category 1: Interpreter Startup

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 1 | `python3 -c print(42)` | **35** | 249 | 116 | **FEX** | 0.30x |
| 2 | `perl -e print` | **14** | 63 | 54 | **FEX** | 0.26x |
| 3 | `ruby -e puts` | **99** | 516 | 225 | **FEX** | 0.44x |

> FEX is fastest in all 3 workloads. Rosetta is 2–4x faster than QEMU, but FEX outperforms Rosetta by another 2–4x.

### Category 2: Package Manager Operations

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 4 | `rpm -V bash` | **73** | 350 | 187 | **FEX** | 0.39x |
| 5 | `rpm -qa \| wc -l` | **134** | 474 | 222 | **FEX** | 0.60x |
| 6 | `dpkg -l \| wc -l` | **19** | 76 | 71 | **FEX** | 0.27x |
| 7 | `pacman -Q \| wc -l` | **34** | 128 | 113 | **FEX** | 0.30x |
| 8 | `dnf repoquery --installed` | **114** | 608 | 281 | **FEX** | 0.41x |

> FEX is fastest in all 5 workloads. Rosetta is 1.7–2.5x faster than QEMU, but FEX outperforms Rosetta by another 1.7–3.7x.

### Category 3: Compilation

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 9 | `gcc hello.c` | **181** | 482 | 316 | **FEX** | 0.57x |
| 10 | `g++ -O2 hello.cpp (STL)` | **682** | 3,775 | 1,322 | **FEX** | 0.52x |
| 11 | `make hello` | **191** | 514 | 345 | **FEX** | 0.55x |

> FEX is fastest in all 3 workloads. Rosetta is 1.5–5.5x faster than QEMU, but FEX outperforms Rosetta by another 1.7–1.9x.

### Category 4: Python Ecosystem

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 12 | `django manage.py check` | **397** | 1,654 | 463 | **FEX** | 0.86x |
| 13 | `ansible localhost ping` | **1,462** | 5,964 | 1,724 | **FEX** | 0.85x |
| 14 | `mypy type-check` | **372** | 1,621 | 510 | **FEX** | 0.73x |

> FEX is fastest in all 3 workloads. django (FEX=397 vs Rosetta=463, 14% faster) and ansible (FEX=1462 vs Rosetta=1724, 15% faster) — FEX wins. mypy: FEX is 27% faster.

### Category 5: Build Tools

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 15 | `perl regex 10k` | **21** | 93 | 67 | **FEX** | 0.31x |
| 16 | `rustc compile hello` | 1,345 | N/A | **881** | **Rosetta** | 1.53x |

> perl regex: FEX is 3.2x faster than Rosetta. rustc: Rosetta is 1.53x faster than FEX. QEMU crashes with SIGKILL (exit 139).

### Category 6: System Tools

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 17 | `Rscript sum(1:1000)` | **568** | 1,215 | 612 | Tie | 0.93x |

> FEX and Rosetta are nearly identical (7% difference). QEMU is 2.1x slower than both.

### Category 7: JIT-on-JIT Runtimes

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta | Notes |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|:------|
| 18 | `java HelloWorld` | 489 | 622 | **421** | **Rosetta** | 1.16x |
| 19 | `node -e console.log(42)` | 436 | 476 | **311** | **Rosetta** | 1.40x |
| 20 | `dotnet --info` | **449** | 1,561 | 908 | **FEX** | 0.49x |

> java and node: Rosetta is faster than FEX. AOT binary translation has an advantage over JIT-on-JIT runtimes.
> dotnet: FEX is 2.0x faster than Rosetta.

## Win/Loss Summary

### FEX vs Rosetta

| Result | Count | Workloads |
|--------|:-----:|-----------|
| **FEX wins** | **16** | python3, perl, ruby, rpm-V, rpm-qa, dpkg, pacman, dnf, gcc, g++ STL, make, django, ansible, mypy, perl regex, dotnet |
| **Tie** (±10%) | **1** | Rscript |
| **Rosetta wins** | **3** | rustc, java, node |

### FEX vs QEMU

| Result | Count | Workloads |
|--------|:-----:|-----------|
| **FEX wins** | **19** | python3, perl, ruby, rpm-V, rpm-qa, dpkg, pacman, dnf, gcc, g++ STL, make, django, ansible, mypy, perl regex, Rscript, java, node, dotnet |
| **Tie** | **0** | — |
| **QEMU wins** | **0** | — |
| **N/A** | **1** | rustc (QEMU: SIGKILL) |

## Key Insights

### 1. FEX Outperforms Rosetta in Most Workloads

FEX is faster than Rosetta in 16/20 workloads.
Dominant in interpreter startup (python3 0.30x, perl 0.26x) and package manager (dpkg 0.27x, dnf 0.41x).
Also leads in compilation (gcc 0.57x, g++ 0.52x, make 0.55x) by 1.7–1.9x.
Python ecosystem now consistently favors FEX (django 0.86x, ansible 0.85x, mypy 0.73x).

### 2. Rosetta Leads in JIT-on-JIT Runtimes and rustc

Rosetta outperforms FEX in java (421ms vs 489ms), node (311ms vs 436ms), and rustc (881ms vs 1,345ms).
AOT binary translation has an advantage during JIT runtime startup phases. FEX's JIT-on-JIT overhead is a factor.
The gap is narrowing: java 1.16x (was 1.21x), node 1.40x (was 1.44x).

### 3. JIT Code Cache Is Key to Performance

FEX's JIT cache improves with repeated execution. In this benchmark (`podman run --rm` creates a new container each time),
the cold/warm ratio is 1.2–8x, but within the same container, cache accumulates for up to **16x** improvement
(dnf check-update: 20.4s → 1.3s). Code cache is per-container and lost when the container is removed (ephemeral).

## Recommendations

| Use Case | Recommended Backend | Reason |
|----------|:-------------------:|--------|
| **libkrun environment** (GPU, etc.) | **FEX** | Rosetta unavailable. FEX faster than QEMU in 19/20 |
| **Node.js workloads** | **Rosetta** > FEX > QEMU | Rosetta=311ms, FEX=436ms, QEMU=476ms |
| **Java workloads** | **Rosetta** > FEX > QEMU | Rosetta=421ms, FEX=489ms, QEMU=622ms |
| **.NET workloads** | **FEX** > Rosetta > QEMU | FEX=449ms, Rosetta=908ms — FEX is 2.0x faster |
| **Python ecosystem** | **FEX** > Rosetta > QEMU | FEX wins all 3: django 0.86x, ansible 0.85x, mypy 0.73x |
| **Package manager ops** | **FEX** > Rosetta > QEMU | FEX is fastest in all 5 workloads |
| **Compilation workloads** | **FEX** > Rosetta > QEMU | FEX fastest in gcc/g++/make; rustc favors Rosetta |
| **Iterative testing / CI** | **FEX** (libkrun) | JIT cache improves with repeated execution |

## Provider Comparison

| Property | Rosetta (applehv) | FEX-Emu (libkrun) | QEMU (libkrun) |
|----------|:-----------------:|:------------------:|:--------------:|
| Emulation method | Binary translation | JIT compilation | Interpreter |
| Code cache | OS-level (persistent) | File-based (per-container, ephemeral) | None |
| Cold→Warm improvement | None (AOT translates upfront) | **1.2–16x** ※ | None |
| Setup | `enable-rosetta` + restart | Custom OS image | No additional setup |
| VM provider | applehv | libkrun | libkrun |
| GPU access | ❌ No | ✅ Supported | ❌ No |
| JIT-on-JIT compatibility | ✅ All OK | ✅ All OK | ✅ All OK |

### Emulation Method Characteristics

**Rosetta — Binary Translation (AOT)**
x86_64→ARM64 translation provided by Apple for macOS. Translates entire binaries ahead-of-time and caches results at the OS level. Fast from the first run with minimal variance across iterations. However, it requires Apple's Virtualization.framework (applehv) and cannot be used in libkrun environments.

**FEX-Emu — JIT Compilation**
JIT-compiles x86_64 instructions to ARM64 at runtime. The first execution is slower due to JIT compilation overhead, but results are saved to a code cache, dramatically accelerating subsequent runs (up to 16x). The code cache is stored per-container as files and accumulates within the same container's lifetime. Lost when the container is removed (ephemeral).

**QEMU — Interpreter**
Interprets x86_64 instructions one by one (qemu-user-static). Does not perform JIT compilation, so there is no code cache concept and performance does not change across iterations. Easiest to set up (no additional configuration), but the slowest of all backends.

> **Important**: Rosetta requires the applehv provider. It cannot be used in libkrun environments (e.g., GPU workloads).
> FEX-Emu is the optimal x86_64 emulation choice for libkrun.

---

**Test Date**: FEX/QEMU: 2026-04-20, Rosetta: 2026-04-06
**Benchmark Environment**: Podman 5.8.1, FEX-2604, kernel 6.19.10, macOS 26.4.1
**Rosetta Note**: Rosetta data from 2026-04-06. Rosetta requires applehv; this Podman installation only supports libkrun.
**Methodology**: `bench/compare.sh` — each workload executed via `podman run --rm bash -c`, all backends **10 iterations, min** value used
**Workloads**: 20 (7 categories: interpreter startup, package manager, compilation, Python ecosystem, build tools, system tools, JIT-on-JIT)
