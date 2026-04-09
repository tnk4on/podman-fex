# Preview Test Suite

This document defines the public test suite for preview users of `podman-fex`.

## Goal

Provide a test set that is:
- easy to run on user machines
- representative of real x86_64 emulation wins
- short enough for preview feedback loops

## Profiles

### デフォルト（引数なし、ユーザー向け推奨）

```bash
./test.sh --connection fex
```

Runs:
- basic tests: T1-T4
- issue reproduction: T5-T11, T13, T14
- workloads: T15, T16

Skipped:
- T12 (`gawk`, heavy apt path)
- T17 (`jemalloc`, heavy apt path)

Typical runtime: 5-8 minutes.

### `--full`（メンテナ / 詳細検証用）

```bash
./test.sh --connection fex --full
```

Runs everything in default mode plus heavy tests:
- T12 (`gawk`)
- T17 (`jemalloc`)

Typical runtime: 8-12 minutes (network dependent).

## Why T12/T17 are excluded by default

Both tests are valid and important, but dominated by package install time (`apt-get update/install`) and fluctuate heavily by mirror/network conditions. For preview users, this introduces noise and makes first-run feedback slower.

Maintainers should still run `--full` before release and when touching compatibility-sensitive code.

## Publishing Recommendation

For release notes and discussion posts, publish:
1. Default result (user-facing confidence)
2. `--full` result (maintainer confidence)

Include `Full log:` path from script output when sharing failures.
