# FEX / QEMU Switching Architecture

## Overview

The FEX-Emu image includes both FEX-Emu and QEMU user-mode emulators. FEX handles x86/x86_64 via binfmt_misc by default; QEMU serves as a fallback and handles x86/x86_64 when FEX is disabled. Only x86/x86_64 and aarch64_be QEMU binaries are pre-installed; other architectures (s390x, ppc64le, etc.) require additional packages.

## Architecture

```
┌─── macOS Host ────────────────────────────────────────────┐
│ containers.conf                                           │
│   [machine]                                               │
│   fex_emu = true/false  ← user config (future upstream)   │
│                         │                                 │
│           podman machine start                            │
│                         │                                 │
│           ApplyFEXEmu() │ (SSH into VM)                   │
└─────────────────────────┼─────────────────────────────────┘
                          ▼
┌─── Fedora CoreOS VM ──────────────────────────────────────┐
│                                                           │
│  /etc/containers/disable-fex-emu   ← SSOT (marker file)  │
│     absent = FEX enabled (default)                        │
│     present = FEX disabled → QEMU fallback                │
│                         │                                 │
│           fex-activation.service (boot)                   │
│                         │                                 │
│              ┌──────────┴──────────┐                      │
│              ▼                     ▼                      │
│        marker absent          marker present              │
│              │                     │                      │
│     FEX binfmt registered    FEX binfmt unregistered      │
│     OCI hook installed       QEMU handles x86_64          │
│     containers.conf set      (pre-installed binfmt)       │
│              │                     │                      │
│     x86_64 → FEXInterpreter  x86_64 → qemu-x86_64        │
│     i386   → qemu-i386        i386   → qemu-i386          │
└───────────────────────────────────────────────────────────┘
```

## Marker File

| State | Marker | Behavior |
|-------|--------|----------|
| **FEX enabled** (default) | `/etc/containers/disable-fex-emu` absent | `fex-activation.sh` sets up FEX binfmt, OCI hook, containers.conf |
| **FEX disabled** | `/etc/containers/disable-fex-emu` present | `fex-activation.sh` unregisters FEX binfmt handlers and exits; QEMU handles x86_64 |

Design rationale: FEX is the default, so absence = enabled is natural. This is the inverse of Rosetta's `/etc/containers/enable-rosetta` (presence = enabled), because Rosetta is opt-in while FEX is opt-out.

## Manual Switching (Current)

```bash
# Disable FEX → QEMU fallback
podman machine ssh -- "sudo touch /etc/containers/disable-fex-emu"
podman machine stop && podman machine start

# Re-enable FEX
podman machine ssh -- "sudo rm /etc/containers/disable-fex-emu"
podman machine stop && podman machine start

# Verify active emulator
podman machine ssh -- "ls /proc/sys/fs/binfmt_misc/ | grep -E 'FEX|qemu'"
```

## Upstream Integration (Future)

When Podman merges FEX support, the marker file will be managed automatically:

1. User sets `fex_emu = false` in `~/.config/containers/containers.conf`
2. `podman machine start` calls `ApplyFEXEmu()` in Go
3. `ApplyFEXEmu()` SSHs into the VM and touches/removes the marker file
4. `fex-activation.service` reads the marker on boot

Users will not need to touch the marker file directly.

```toml
# ~/.config/containers/containers.conf
[machine]
fex_emu = false        # Disable FEX, use QEMU for x86_64
fex_code_cache = true  # JIT code caching (independent of fex_emu)
```

## Code Cache Toggle

FEX JIT code caching is a separate setting from FEX enable/disable. It controls whether FEX saves compiled code to disk for reuse.

| Setting | Effect |
|---------|--------|
| `fex_code_cache = true` (default) | FEX caches JIT-compiled code per container |
| `fex_code_cache = false` | FEX recompiles on every execution |

The code cache is ephemeral (destroyed when the container exits) and stored at `/tmp/fex-emu/cache/` inside each container.

Current toggle (via containers.conf drop-in):

```bash
# Disable code cache
podman machine ssh -- 'mkdir -p ~/.config/containers/containers.conf.d && \
  printf "[containers]\nenv = [\"FEX_ENABLECODECACHINGWIP=0\", {append=true}]\n" \
  > ~/.config/containers/containers.conf.d/fex-code-cache.conf'

# Re-enable code cache (remove drop-in → base value of =1 applies)
podman machine ssh -- 'rm -f ~/.config/containers/containers.conf.d/fex-code-cache.conf'
```

## What Each Emulator Handles

| Architecture | FEX enabled (default) | FEX disabled |
|---|---|---|
| x86 / x86_64 | **FEX-Emu** (JIT) | **QEMU** (interpreter) |
| arm64 (native) | Direct execution | Direct execution |

> **Note**: Only x86/x86_64 and aarch64_be QEMU binaries are pre-installed. Other architectures (s390x, ppc64le, riscv64, etc.) require installing additional `qemu-user-static-*` packages.
