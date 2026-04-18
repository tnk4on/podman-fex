# Cross-Backend Benchmark: FEX-Emu vs QEMU vs Rosetta

## Executive Summary

Comparison of x86_64 container emulation performance across 3 backends on Apple Silicon (M1 Max).
20 practical workloads in 7 categories, evaluated by min values.

| Backend | VM Provider | Emulation | Interpreter Startup | Package Mgr | Compilation |
|---------|-------------|-----------|:---:|:---:|:---:|
| **FEX-Emu** | libkrun | JIT | 15–102ms | 20–139ms | 191–1,382ms |
| **QEMU** | libkrun | qemu-user-static | 68–577ms | 131–669ms | 529–4,203ms |
| **Rosetta** | applehv | Binary translation | 54–225ms | 71–281ms | 316–1,322ms |

**Conclusions**:
- **FEX is faster than QEMU in 18/20 workloads** — dominant across all categories
- **FEX vs Rosetta: 14 wins / 3 ties / 3 losses** — FEX decisively leads in interpreter startup, package manager, and compilation
- **Rosetta is faster in rustc / java / node** — AOT translation favors JIT runtimes
- **FEX is the only high-speed emulation option for libkrun** — Rosetta is exclusive to applehv

## Environment

| Item | Detail |
|------|--------|
| Host | Apple M1 Max, macOS 26.3.1 |
| Podman | 6.0.0-dev (`/opt/podman/bin/podman`) |
| FEX VM | libkrun, 4 CPU / 8 GiB, Fedora CoreOS + FEX-Emu (`quay.io/tnk4on/machine-os:5.8`) |
| FEX Build | FEX-2603, `-DCMAKE_BUILD_TYPE=Release`, static-pie |
| FEX Kernel | `6.19.7-200.fc43.aarch64` (standard, non-TSO) |
| QEMU VM | libkrun, 4 CPU / 8 GiB, Fedora CoreOS (default image, qemu-user-static) |
| Rosetta VM | applehv, 4 CPU / 8 GiB, Fedora CoreOS (default image, Rosetta binary translation) |
| Date | 2026-04-08 |

> **Methodology**: Each workload is executed via `podman run --rm bash -c`. All backends run 10 iterations and the minimum value is taken. The OCI hook sets `FEX_APP_*` environment variables so the JIT code cache is active.

## Full Results

20 workloads × 3 backends. **min values** are used. **Winner** = fastest backend (Tie = ±10%).

### Category 1: Interpreter Startup

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 1 | `python3 -c print(42)` | **37** | 390 | 116 | **FEX** | 0.32x |
| 2 | `perl -e print` | **15** | 68 | 54 | **FEX** | 0.28x |
| 3 | `ruby -e puts` | **102** | 577 | 225 | **FEX** | 0.45x |

> FEX is fastest in all 3 workloads. Rosetta is 2–3x faster than QEMU, but FEX outperforms Rosetta by another 2–4x.

### Category 2: Package Manager Operations

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 4 | `rpm -V bash` | **76** | 397 | 187 | **FEX** | 0.41x |
| 5 | `rpm -qa \| wc -l` | **139** | 604 | 222 | **FEX** | 0.63x |
| 6 | `dpkg -l \| wc -l` | **20** | 131 | 71 | **FEX** | 0.28x |
| 7 | `pacman -Q \| wc -l` | **43** | 186 | 113 | **FEX** | 0.38x |
| 8 | `dnf repoquery --installed` | **121** | 669 | 281 | **FEX** | 0.43x |

> FEX is fastest in all 5 workloads. Rosetta is 2–2.5x faster than QEMU, but FEX outperforms Rosetta by another 1.6–3.6x.

### Category 3: Compilation

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 9 | `gcc hello.c` | **191** | 529 | 316 | **FEX** | 0.60x |
| 10 | `g++ -O2 hello.cpp (STL)` | **692** | 4,203 | 1,322 | **FEX** | 0.52x |
| 11 | `make hello` | **198** | 567 | 345 | **FEX** | 0.57x |

> FEX is fastest in all 3 workloads. Rosetta is 1.6–3.2x faster than QEMU, but FEX outperforms Rosetta by another 1.7–1.9x.

### Category 4: Python Ecosystem

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 12 | `django manage.py check` | **437** | 1,706 | 463 | Tie | 0.94x |
| 13 | `ansible localhost ping` | **1,657** | 6,605 | 1,724 | Tie | 0.96x |
| 14 | `mypy type-check` | **380** | 1,611 | 510 | **FEX** | 0.75x |

> django (FEX=437 vs Rosetta=463) and ansible (FEX=1657 vs Rosetta=1724) are within ±10% — Tie. mypy: FEX is 25% faster — FEX wins.

### Category 5: Build Tools

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 15 | `perl regex 10k` | **23** | 99 | 67 | **FEX** | 0.34x |
| 16 | `rustc compile hello` | 1,382 | ~~438~~ | **881** | **Rosetta** | 1.57x |

> perl regex: FEX is 2.9x faster than Rosetta. rustc: Rosetta is 1.57x faster than FEX. QEMU fails with SIGSEGV (exit 139).

### Category 6: System Tools

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 17 | `Rscript sum(1:1000)` | 592 | 1,318 | 612 | Tie | 0.97x |

> FEX and Rosetta are nearly identical (3% difference). QEMU is 2.2x slower than both.

### Category 7: JIT-on-JIT Runtimes

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta | Notes |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|:------|
| 18 | `java HelloWorld` | 509 | 623 | **421** | **Rosetta** | 1.21x |
| 19 | `node -e console.log(42)` | 449 | 468 | **311** | **Rosetta** | 1.44x |
| 20 | `dotnet --info` | **482** | 1,682 | 908 | **FEX** | 0.53x |

> java and node: Rosetta is faster than FEX. AOT binary translation has an advantage over JIT-on-JIT runtimes.
> dotnet: FEX is 1.9x faster than Rosetta.

## Win/Loss Summary

### FEX vs Rosetta

| Result | Count | Workloads |
|--------|:-----:|-----------|
| **FEX wins** | **14** | python3, perl, ruby, rpm-V, rpm-qa, dpkg, pacman, dnf, gcc, g++ STL, make, mypy, perl regex, dotnet |
| **Tie** (±10%) | **3** | django, ansible, Rscript |
| **Rosetta wins** | **3** | rustc, java, node |

### FEX vs QEMU

| Result | Count | Workloads |
|--------|:-----:|-----------|
| **FEX wins** | **18** | python3, perl, ruby, rpm-V, rpm-qa, dpkg, pacman, dnf, gcc, g++ STL, make, django, ansible, mypy, perl regex, Rscript, java, dotnet |
| **Tie** | **1** | node (FEX=449, QEMU=468) |
| **QEMU wins** | **0** | — |
| **N/A** | **1** | rustc (QEMU: SIGSEGV) |

## Key Insights

### 1. FEX Outperforms Rosetta in Most Workloads

FEX is faster than Rosetta in 14/20 workloads.
Dominant in interpreter startup (python3 0.32x, perl 0.28x) and package manager (dpkg 0.28x, dnf 0.43x).
Also leads in compilation (gcc 0.60x, g++ 0.52x, make 0.57x) by 1.7–1.9x.

### 2. Rosetta Leads in JIT-on-JIT Runtimes and rustc

Rosetta outperforms FEX in java (421ms vs 509ms), node (311ms vs 449ms), and rustc (881ms vs 1,382ms).
AOT binary translation has an advantage during JIT runtime startup phases. FEX's JIT-on-JIT overhead is a factor.
Python ecosystem: mypy favors FEX (380ms vs 510ms). django / ansible are Tie — closely matched.

### 3. JIT Code Cache Is Key to Performance

FEX's JIT cache improves with repeated execution. In this benchmark (`podman run --rm` creates a new container each time),
the cold/warm ratio is 1.2–8x, but within the same container, cache accumulates for up to **16x** improvement
(dnf check-update: 20.4s → 1.3s). Code cache is per-container and lost when the container is removed (ephemeral).

## Recommendations

| Use Case | Recommended Backend | Reason |
|----------|:-------------------:|--------|
| **libkrun environment** (GPU, etc.) | **FEX** | Rosetta unavailable. FEX faster than QEMU in 18/20 |
| **Node.js workloads** | **Rosetta** > FEX > QEMU | Rosetta=311ms, FEX=449ms, QEMU=468ms |
| **Java workloads** | **Rosetta** > FEX > QEMU | Rosetta=421ms, FEX=509ms, QEMU=623ms |
| **.NET workloads** | **FEX** > Rosetta > QEMU | FEX=482ms, Rosetta=908ms — FEX is 1.9x faster |
| **Python ecosystem** | **FEX** ≈ Rosetta > QEMU | django/ansible/mypy all Tie — FEX and Rosetta closely matched |
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

**Test Date**: April 2026 (FEX: 2026-04-08, Rosetta/QEMU: 2026-04-06)
**Environment**: Podman 6.0.0-dev, M1 Max macOS
**Methodology**: `bench/compare.sh` — each workload executed via `podman run --rm bash -c`, all backends **10 iterations, min** value used
**Workloads**: 20 (7 categories: interpreter startup, package manager, compilation, Python ecosystem, build tools, system tools, JIT-on-JIT)
