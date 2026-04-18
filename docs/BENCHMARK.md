# JIT Code Cache Benchmark Results

Comprehensive benchmark of FEX-Emu's JIT code cache effect across 30+ workloads.

## Methodology

- **Environment**: Podman Machine (libkrun, Fedora CoreOS) on Apple Silicon (M1 Max)
- **Method**: Single container, 5 iterations per workload
- **Comparison**: Run 1 (cold JIT) vs Run 4/5 (warm JIT cache)
- **Isolation**: Application-level caches (dnf metadata, pacman sync DB, etc.) are cleared where noted
- **Code cache**: Enabled via `FEX_ENABLECODECACHINGWIP=1` (default)

## How JIT Cache Works

FEX-Emu writes JIT-compiled code to the cache **asynchronously** — the compiled results from Run N are flushed to disk in the background and become available from Run N+1 onward:

- **Run 1**: Full JIT compilation (slowest)
- **Run 2**: Cache from Run 1 is still being written; may actually be **slower** than Run 1
- **Run 3+**: Cache is fully populated; execution approaches near-native speed

> Code cache is **ephemeral** (per-container lifetime). When a container is removed, the cache is lost and JIT recompilation occurs on the next run.

## Full Results

Sorted by speedup factor (descending).

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
| `pacman -Q \| wc -l` | archlinux | 1,305ms | 105ms | **12.4x** | Package manager (list installed) |
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

## Runtimes with No Cache Benefit

JVM-based runtimes, .NET, and Node.js show minimal cache benefit because their own JIT compilers (HotSpot, CoreCLR, V8) create a "JIT-on-JIT" overhead that dominates execution time.

| Runtime | Tool | Run 1 | Run 5 | Notes |
|---------|------|------:|------:|-------|
| Java 21 | `java -version` | 4,552ms | 3,988ms | HotSpot JIT-on-JIT |
| Java 21 | `javac -version` | 6,895ms | 6,540ms | HotSpot JIT-on-JIT |
| .NET 8 | `dotnet --version` | 13,248ms | 9,375ms | CoreCLR JIT-on-JIT |
| Node.js 22 | `npm --version` | 24,870ms | 16,870ms | V8 JIT-on-JIT |
| Clang 18 | `clang --version` | 2,424ms | 1,660ms | Binary too large |
| R 4.4 | `Rscript hello` | 7,161ms | 3,540ms | BEAM-like overhead |
| Haskell 9.8 | `ghc --version` | 1,501ms | 150ms | Erratic (cache spikes) |

## Tested Images

python:3.12, gcc:14-bookworm, perl:5, ruby:3.3, php:8.3, golang:1.23, rust:1.83, haskell:9.8-slim, elixir:1.17-slim, r-base:4.4.1, maven:3.9, debian:bookworm, ubuntu:24.04, fedora:42, ubi9, archlinux, silkeh/clang:18-bookworm, eclipse-temurin:21-jdk-jammy, mcr.microsoft.com/dotnet/sdk:8.0, node:22-slim
