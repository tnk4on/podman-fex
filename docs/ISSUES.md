# Podman x86_64 Emulation Issues: Unresolved Rosetta/QEMU Issue List

> A comprehensive list of unresolved issues in the containers/podman repository where x86_64 emulation using Rosetta or QEMU fails on Apple Silicon (macOS aarch64), limited to those that provide `podman run` or `podman build` reproduction commands.

## Summary Statistics

| Item | Count |
|------|-------|
| **Total issues surveyed** | 18 |
| OPEN | 14 |
| CLOSED (root cause unresolved) | 4 |
| **Failure categories** | |
| 🔴 Crash / SIGSEGV | 7 |
| 🟡 Hang / Freeze | 5 |
| 🟠 Build failure | 4+1 |
| 🟣 Behavioral bug | 1 |
| **Test types** | |
| `podman run` (immediately testable) | 12 |
| `podman build` (requires Dockerfile) | 5 |
| Load test (requires app setup) | 1 |
| **Root-cause emulator** | |
| Rosetta | 9 |
| QEMU | 7 |
| BuildKit-specific | 2 |

---

## Issues by Category

### 🔴 Crash / SIGSEGV (7)

#### 1. [#28184](https://github.com/containers/podman/issues/28184) — MSSQL 2025 AVX Instruction Crash (Rosetta)
- **Status**: OPEN
- **Symptom**: Rosetta 2 cannot correctly emulate AVX/XSAVE instructions, causing MSSQL 2025 container to fail with assertion failure at startup
- **Error**: `assertion failed [x86_avx_state_ptr->xsave_header.xfeatures == kSupportedXFeatureBits]`
- **Reproduction**:
```bash
podman run -e 'ACCEPT_EULA=Y' -e 'SA_PASSWORD=Str0ng!Passw0rd' \
  -p 1433:1433 --platform linux/amd64 \
  mcr.microsoft.com/mssql/server:2025-latest
```

---

#### 2. [#27078](https://github.com/containers/podman/issues/27078) — MSSQL 2022 Segmentation Fault (Rosetta)
- **Status**: OPEN
- **Symptom**: MSSQL 2022 crashes with SIGSEGV under Rosetta. Works in Docker Desktop / Rancher Desktop
- **Error**: `Segmentation fault (core dumped)`
- **Reproduction**:
```bash
podman run --memory=4096M -e "ACCEPT_EULA=Y" \
  -e "MSSQL_SA_PASSWORD=SecurePassword123$" \
  -p 1433:1433 --name sql2022 --rm -i \
  mcr.microsoft.com/mssql/server:2022-latest
```

---

#### 3. [#28169](https://github.com/containers/podman/issues/28169) — rustc SIGSEGV (QEMU)
- **Status**: OPEN
- **Symptom**: x86_64 Rust compiler image crashes with SIGSEGV under QEMU during realloc
- **Error**: `qemu: uncaught target signal 11 (Segmentation fault) - core dumped`
- **Reproduction**:
```bash
podman run --rm --platform linux/amd64 \
  --entrypoint rustc \
  docker.io/library/rust:1.93.0-bookworm -vV
```

---

#### 4. [#26036](https://github.com/containers/podman/issues/26036) — PyArrow SIGSEGV (QEMU)
- **Status**: OPEN
- **Symptom**: Importing Python PyArrow crashes QEMU. Can only be terminated with kill -9
- **Error**: `qemu: uncaught target signal 11 (Segmentation fault) - core dumped`
- **Reproduction**:
```bash
podman run --arch amd64 python:3.11-slim \
  bash -c 'pip install pyarrow==20.0.0; python -c "import pyarrow"'
```

---

#### 5. [#27320](https://github.com/containers/podman/issues/27320) — jemalloc SIGSEGV (QEMU)
- **Status**: OPEN
- **Symptom**: Loading jemalloc causes QEMU SIGSEGV
- **Error**: `qemu: uncaught target signal 11 (Segmentation fault) - core dumped`
- **Reproduction**:
```bash
podman run -it --arch amd64 docker.io/library/ubuntu:latest
# Inside the container:
apt update && apt install libjemalloc2
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 /usr/bin/bash
```

---

#### 5b. [#23219](https://github.com/containers/podman/issues/23219) — gawk SIGSEGV (QEMU)
- **Status**: OPEN
- **Symptom**: `gawk --version` crashes with QEMU SIGSEGV in OpenWrt imagebuilder container, breaking the firmware build system
- **Error**: `qemu: uncaught target signal 11 (Segmentation fault) - core dumped`
- **Reproduction**:
```bash
podman run --rm --platform linux/amd64 debian:bookworm-slim \
  sh -c 'apt-get update -qq && apt-get install -y -qq gawk && gawk --version'
```

---

#### 5c. [D#27601](https://github.com/containers/podman/discussions/27601) — redis-cluster SIGSEGV (QEMU)
- **Status**: OPEN (Discussion)
- **Symptom**: `podman run duyquyen/redis-cluster` crashes with QEMU SIGSEGV on M1 Mac. Occurs with both Apple HyperVisor + Rosetta and libkrun
- **Error**: `qemu: uncaught target signal 11 (Segmentation fault) - core dumped`
- **Reproduction**:
```bash
podman run --rm --platform linux/amd64 docker.io/duyquyen/redis-cluster redis-server --version
```

---

### 🟡 Hang / Freeze (5)

#### 6. [#27210](https://github.com/containers/podman/issues/27210) — Arch Linux Hang (Rosetta)
- **Status**: OPEN
- **Symptom**: Interactive shell hangs in amd64 Arch Linux container. Cannot be interrupted with Ctrl+C
- **Reproduction**:
```bash
podman run -it --arch amd64 archlinux
```

---

#### 7. [#26572](https://github.com/containers/podman/issues/26572) — Node.js/Express Freeze (Rosetta)
- **Status**: OPEN
- **Symptom**: Node.js Express app freezes during load testing in Rosetta-enabled linux/amd64 container. Switching to QEMU resolves the issue
- **Workaround**: Use QEMU
- **Reproduction** (overview):
```bash
# 1. Enable Rosetta
# 2. Build Express app image for linux/amd64
podman build --platform linux/amd64 -t express-app .
# 3. Container freezes when parallel HTTP requests are sent
podman run --platform linux/amd64 express-app
```

---

#### 8. [#27817](https://github.com/containers/podman/issues/27817) — Fedora Shell Hang (Rosetta) ⚠️ CLOSED
- **Status**: CLOSED
- **Symptom**: `podman run --platform linux/amd64 -it fedora sh` hangs. `uname -m` works. Fedora-specific issue
- **Reproduction**:
```bash
podman run --rm --platform linux/amd64 -it fedora sh
```

---

#### 9. [#27799](https://github.com/containers/podman/issues/27799) — Ubuntu 25.10 Terminal Attach Failure ⚠️ CLOSED
- **Status**: CLOSED
- **Symptom**: bash fails to start and gets stuck in amd64 Ubuntu 25.10 image
- **Reproduction**:
```bash
podman run -it --arch amd64 ubuntu:25.10 bash
```

---

#### 9b. [#23269](https://github.com/containers/podman/issues/23269) — Next.js Build Hang / SWC (Rosetta/QEMU)
- **Status**: OPEN
- **Symptom**: `npm run build` (Next.js) consumes CPU indefinitely and hangs permanently in linux/amd64 container. Occurs during SWC (Rust-based JS compiler) binary loading
- **Workaround**: Use ARM64 native images
- **Reproduction**:
```bash
podman run --rm --platform linux/amd64 node:20-slim \
  bash -c 'cd /tmp && npm init -y && npm install @swc/core && \
  node -e "const s = require(\"@swc/core\"); console.log(s.transformSync(\"const x: number = 1\", {jsc:{parser:{syntax:\"typescript\"}}}).code)"'
```

---

### 🟠 Build Failures (4)

#### 10. [#25272](https://github.com/containers/podman/issues/25272) — Angular Build Hang (QEMU)
- **Status**: OPEN
- **Symptom**: `ng build` step stalls permanently. Builds successfully on arm64
- **Reproduction**:
```bash
podman build --platform linux/amd64 -t ui -f ./ui/Dockerfile.dev . \
  --build-arg NG_APP_ENV=development
```

---

#### 11. [#26919](https://github.com/containers/podman/issues/26919) — Go Build godump (Rosetta)
- **Status**: OPEN
- **Symptom**: Go runtime panics/godumps during `go build` step in `podman build`
- **Reproduction** (overview):
```bash
# Build an image that runs go build in its Dockerfile
podman build .
```

---

#### 12. [#26881](https://github.com/containers/podman/issues/26881) — Podman 5.6.0 linux/amd64 Build & Runtime Breakdown ⚠️ CLOSED
- **Status**: CLOSED (fixed by downgrading to Podman 5.5.2)
- **Symptom**: Go image build and execution panics on linux/amd64 with Podman 5.6.0
- **Reproduction**:
```bash
# Prepare a Dockerfile:
# FROM --platform=linux/amd64 golang:1.24-alpine
# ... go build ...
podman build .
```

---

#### 13. [#24647](https://github.com/containers/podman/issues/24647) — sudo Fails with Rosetta + BuildKit
- **Status**: OPEN
- **Symptom**: `sudo` inside x86_64 container fails with `nosuid` error under BuildKit + Rosetta 2
- **Error**: `sudo: effective uid is not 0, is /usr/bin/sudo on a file system with the 'nosuid' option set`
- **Reproduction**:
```bash
# Dockerfile:
# FROM alpine
# RUN apk add shadow sudo
# RUN echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers
# RUN useradd --create-home --non-unique --uid 1000 --groups wheel user
# USER 1000
# RUN sudo /bin/ls
docker buildx build --platform=linux/x86_64 . --load
# (podman build --platform=linux/x86_64 . works fine — BuildKit-specific)
```

---

#### 14. [#24000](https://github.com/containers/podman/issues/24000) — buildkit_qemu_emulator SELinux Error
- **Status**: OPEN
- **Symptom**: Building amd64 images via BuildKit produces SELinux xattr errors
- **Error**: `failed to set xattr "security.selinux": operation not supported`
- **Reproduction**:
```bash
DOCKER_BUILDKIT=1 docker build . --tag test:latest \
  --platform=linux/amd64 -f Dockerfile --load
```

---

### 🟣 Behavioral Bug (1)

#### 15. [#26656](https://github.com/containers/podman/issues/26656) — su -l Does Not Start Login Shell (Rosetta)
- **Status**: OPEN
- **Symptom**: `su -l` does not start a login shell on Apple Silicon macOS + Rosetta. Bash reports "Not login shell", breaking containers that depend on `su` (e.g., IBM DB2)
- **Reproduction**:
```bash
podman run --rm --platform linux/amd64 registry.access.redhat.com/ubi8:latest \
  sh -c 'useradd appuser && su -l appuser -c "shopt -q login_shell && echo Login_shell || echo Not_login_shell"'
```

---

## FEX-Emu Test Matrix

The following is a list of test commands to verify whether FEX-Emu improves each issue. All `podman run` commands use `--arch amd64`.

| # | Issue | Category | Test Command | Expected Improvement |
|---|-------|----------|-------------|---------------------|
| 1 | #28184 | MSSQL 2025 AVX | `podman run -e 'ACCEPT_EULA=Y' -e 'SA_PASSWORD=Str0ng!Passw0rd' -p 1433:1433 --platform linux/amd64 mcr.microsoft.com/mssql/server:2025-latest` | Depends on FEX-Emu AVX support |
| 2 | #27078 | MSSQL 2022 SIGSEGV | `podman run --memory=4096M -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=SecurePassword123$" -p 1433:1433 --rm mcr.microsoft.com/mssql/server:2022-latest` | Possible if caused by QEMU/Rosetta memory management |
| 3 | #28169 | rustc SIGSEGV | `podman run --rm --platform linux/amd64 --entrypoint rustc docker.io/library/rust:1.93.0-bookworm -vV` | Possible if caused by realloc implementation |
| 4 | #26036 | PyArrow SIGSEGV | `podman run --arch amd64 python:3.11-slim bash -c 'pip install pyarrow==20.0.0; python -c "import pyarrow"'` | Depends on instruction emulation |
| 5 | #27320 | jemalloc SIGSEGV | `podman run -it --arch amd64 ubuntu:latest` → `apt install libjemalloc2; LD_PRELOAD=... bash` | Depends on memory allocator compatibility |
| 5b | #23219 | gawk SIGSEGV | `podman run --rm --platform linux/amd64 debian:bookworm-slim sh -c 'apt-get update && apt-get install -y gawk && gawk --version'` | Depends on instruction emulation |
| 5c | D#27601 | redis-cluster SIGSEGV | `podman run --rm --platform linux/amd64 docker.io/duyquyen/redis-cluster redis-server --version` | Possible if jemalloc-related |
| 6 | #27210 | Arch Linux hang | `podman run -it --arch amd64 archlinux` | Likely if caused by terminal I/O |
| 7 | #26572 | Node.js freeze | Express app build & load test | Possible if caused by thread scheduling |
| 8 | #27817 | Fedora hang | `podman run --rm --platform linux/amd64 -it fedora sh` | CLOSED but worth testing |
| 9 | #27799 | Ubuntu hang | `podman run -it --arch amd64 ubuntu:25.10 bash` | CLOSED but worth testing |
| 9b | #23269 | SWC/Next.js hang | `podman run --rm --platform linux/amd64 node:20-slim bash -c 'npm install @swc/core && node -e ...'` | ✅ Fixed by FEX build image update |
| 10 | #25272 | Angular build hang | `podman build --platform linux/amd64` (Angular) | Possible if CPU-bound build issue |
| 11 | #26919 | Go build godump | `podman build` (Go microservice) | Depends on Go runtime compatibility |
| 12 | #24647 | sudo nosuid | BuildKit + x86_64 `sudo` | Possible due to binfmt_misc differences |
| 13 | #24000 | SELinux xattr | BuildKit + amd64 build | Likely an SELinux config issue unrelated to FEX |
| 14 | #26881 | Go build panic | `podman build` (Go hello world) | Go 1.24+ FIPS/AES issue |
| 15 | #26656 | su -l bug | `podman run --rm --platform linux/amd64 ubi8 sh -c 'useradd appuser && su -l appuser -c ...'` | Depends on syscall emulation |

## FEX-Emu Test Execution Plan

Tests are organized in the `tests/` directory within the [podman-fex](https://github.com/tnk4on/podman-fex) repository.

```
tests/
├── test-fex.sh              # Unified runner (61 tests, 7 categories)
├── lib-test.sh              # Shared test library (XFAIL support)
├── run/                     # podman run issue reproduction scripts
│   ├── 01-mssql-2025.sh     # #28184 — MSSQL 2025 AVX
│   ├── 02-mssql-2022.sh     # #27078 — MSSQL 2022 SIGSEGV
│   ├── 03-rustc.sh          # #28169 — rustc SIGSEGV
│   ├── 04-pyarrow.sh        # #26036 — PyArrow SIGSEGV
│   ├── 05-jemalloc.sh       # #27320 — jemalloc SIGSEGV
│   ├── 06-archlinux.sh      # #27210 — Arch Linux hang
│   ├── 07-fedora.sh         # #27817 — Fedora hang
│   ├── 08-ubuntu.sh         # #27799 — Ubuntu hang
│   ├── 12-nodejs-express.sh # #26572 — Express load test
│   ├── 13b-gawk.sh          # #23219 — gawk SIGSEGV
│   ├── 14-redis-cluster.sh  # D#27601 — redis-cluster SIGSEGV
│   ├── 15-swc-nextjs.sh     # #23269 — SWC/Next.js
│   └── 16-su-login-shell.sh # #26656 — su -l behavioral bug
├── build/                   # podman build test contexts
│   ├── 09-go-hello/         # #26881 — Go build
│   ├── 10-angular/          # #25272 — Angular build
│   ├── 11-sudo-buildkit/    # #24647 — sudo + BuildKit
│   ├── 12-nodejs-express/   # #26572 — Node.js Express
│   └── 13-go-build/         # #26919 — Go build godump
└── results/                 # Test output logs (gitignored)
```

### Running Tests

```bash
# Full test suite (61 tests)
bash tests/test-fex.sh --connection <machine-name>

# Specific category
bash tests/test-fex.sh --connection <machine-name> --category issue

# Specific tests
bash tests/test-fex.sh --connection <machine-name> --test I16,I01

# List all tests
bash tests/test-fex.sh --list
```

### Known Failures (XFAIL)

The following tests are expected to fail and are tracked as XFAIL:

| Test | Issue | Reason |
|------|-------|--------|
| I04 | #25272 | Angular build hangs (V8/esbuild JIT timeout) |
| I08 | #26881 | Go 1.24+ FIPS/AES SIGILL |
| I09 | #26919 | Go godump requires full project context |
| I10 | #27078 | MSSQL 2022 requires AVX support |
| I17 | #28184 | MSSQL 2025 requires AVX support |

## Notes

- **Closed issues** (#27817, #27799, #26881) are included in the test matrix because the underlying emulation problems may not be fully resolved
- **BuildKit-specific issues** (#24647, #24000) may behave differently depending on FEX-Emu's binfmt_misc registration method
- **Node.js freeze** (#26572) requires a load test environment but is reproduced using a minimal Express server
- **Angular build** (#25272) uses a minimal Angular project to reproduce the `ng build` hang
- **#24000 (SELinux xattr)** is excluded from testing as it is an SELinux configuration issue unrelated to FEX-Emu
- **gawk (#23219)** — the original issue uses an OpenWrt imagebuilder (403 Forbidden), so Debian bookworm + apt-get install gawk is used as an alternative
- **redis-cluster (D#27601)** is a Discussion rather than an Issue, but is useful for reproducing QEMU SIGSEGV
- **SWC/Next.js (#23269)** — fixed by FEX build image update (2026-04-06)
- **su -l (#26656)** is a Rosetta-specific behavioral bug; FEX-Emu correctly starts a login shell
