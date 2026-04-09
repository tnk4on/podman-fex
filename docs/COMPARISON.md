# Cross-Backend Benchmark: FEX-Emu vs QEMU vs Rosetta

## Executive Summary

Apple Silicon (M1 Max) での x86_64 コンテナエミュレーション性能を 3 バックエンドで比較。
20 の実用的ワークロードを 7 カテゴリに分類し、min 値で評価。

| Backend | VM Provider | Emulation | Interpreter Startup | Package Mgr | Compilation |
|---------|-------------|-----------|:---:|:---:|:---:|
| **FEX-Emu** | libkrun | JIT | 15–102ms | 20–139ms | 191–1,382ms |
| **QEMU** | libkrun | qemu-user-static | 68–577ms | 131–669ms | 529–4,203ms |
| **Rosetta** | applehv | Binary translation | 54–225ms | 71–281ms | 316–1,322ms |

**結論**:
- **FEX は 18/20 ワークロードで QEMU より高速** — 全カテゴリで優位
- **FEX vs Rosetta: 14 勝 / 3 引 / 3 敗** — Interpreter startup・Package manager・Compilation で FEX 圧倒的優位
- **Rosetta は rustc / java / node で FEX より高速** — AOT 翻訳が JIT ランタイムに有利
- **libkrun 環境では FEX が唯一の高速エミュレーション選択肢** — Rosetta は applehv 専用のため使用不可

## Environment

| Item | Detail |
|------|--------|
| Host | Apple M1 Max, macOS 26.3.1 |
| Podman | 6.0.0-dev (`/opt/podman/bin/podman`) |
| FEX VM | libkrun, 4 CPU / 8 GiB, Fedora CoreOS + FEX-Emu (`quay.io/tnk4on/machine-os:5.8`) |
| FEX Build | FEX-2603, `-DCMAKE_BUILD_TYPE=Release`, static-pie |
| FEX Kernel | `6.19.7-200.fc43.aarch64` (標準、非 TSO) |
| QEMU VM | libkrun, 4 CPU / 8 GiB, Fedora CoreOS (default image, qemu-user-static) |
| Rosetta VM | applehv, 4 CPU / 8 GiB, Fedora CoreOS (default image, Rosetta binary translation) |
| Date | 2026-04-08 |

> **測定方式**: 各ワークロードを `podman run --rm bash -c` で実行。全バックエンド 10 回実行で min を取得。OCI hook が `FEX_APP_*` 環境変数を設定し、JIT コードキャッシュが機能する。

## Full Results

20 ワークロード × 3 バックエンド。**min 値**（最小値）を採用。**Winner** = fastest backend (Tie = ±10%)。

### Category 1: Interpreter Startup

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 1 | `python3 -c print(42)` | **37** | 390 | 116 | **FEX** | 0.32x |
| 2 | `perl -e print` | **15** | 68 | 54 | **FEX** | 0.28x |
| 3 | `ruby -e puts` | **102** | 577 | 225 | **FEX** | 0.45x |

> FEX が全 3 ワークロードで最速。Rosetta も QEMU の 2–3x 高速だが、FEX はその Rosetta をさらに 2–4x 上回る。

### Category 2: Package Manager Operations

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 4 | `rpm -V bash` | **76** | 397 | 187 | **FEX** | 0.41x |
| 5 | `rpm -qa \| wc -l` | **139** | 604 | 222 | **FEX** | 0.63x |
| 6 | `dpkg -l \| wc -l` | **20** | 131 | 71 | **FEX** | 0.28x |
| 7 | `pacman -Sy` | **43** | 186 | 113 | **FEX** | 0.38x |
| 8 | `dnf repoquery --installed` | **121** | 669 | 281 | **FEX** | 0.43x |

> FEX が全 5 ワークロードで最速。Rosetta も QEMU の 2–2.5x 高速だが、FEX は Rosetta をさらに 1.6–3.6x 上回る。

### Category 3: Compilation

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 9 | `gcc hello.c` | **191** | 529 | 316 | **FEX** | 0.60x |
| 10 | `g++ -O2 hello.cpp (STL)` | **692** | 4,203 | 1,322 | **FEX** | 0.52x |
| 11 | `make hello` | **198** | 567 | 345 | **FEX** | 0.57x |

> FEX が全 3 ワークロードで最速。Rosetta は QEMU の 1.6–3.2x 高速だが、FEX は Rosetta をさらに 1.7–1.9x 上回る。

### Category 4: Python Ecosystem

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 12 | `django manage.py check` | **437** | 1,706 | 463 | Tie | 0.94x |
| 13 | `ansible localhost ping` | **1,657** | 6,605 | 1,724 | Tie | 0.96x |
| 14 | `mypy type-check` | **380** | 1,611 | 510 | **FEX** | 0.75x |

> django (FEX=437 vs Rosetta=463) と ansible (FEX=1657 vs Rosetta=1724) は ±10% 以内で Tie。mypy は FEX が 25% 優位で FEX wins。

### Category 5: Build Tools

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 15 | `perl regex 10k` | **23** | 99 | 67 | **FEX** | 0.34x |
| 16 | `rustc compile hello` | 1,382 | ~~438~~ | **881** | **Rosetta** | 1.57x |

> perl regex: FEX が Rosetta の 2.9x 高速。rustc: Rosetta が FEX の 1.57x 高速。QEMU は SIGSEGV (exit 139) で失敗。

### Category 6: System Tools

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 17 | `Rscript sum(1:1000)` | 592 | 1,318 | 612 | Tie | 0.97x |

> FEX と Rosetta がほぼ同等 (3% 差)。QEMU は両者の 2.2x 遅い。

### Category 7: JIT-on-JIT Runtimes

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta | Notes |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|:------|
| 18 | `java HelloWorld` | 509 | 623 | **421** | **Rosetta** | 1.21x |
| 19 | `node -e console.log(42)` | 449 | 468 | **311** | **Rosetta** | 1.44x |
| 20 | `dotnet --info` | **482** | 1,682 | 908 | **FEX** | 0.53x |

> java と node で Rosetta が FEX より高速。AOT バイナリ翻訳が JIT-on-JIT ランタイムに有利。
> dotnet は FEX が Rosetta の 1.9x 高速。

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

### 1. FEX が大半のワークロードで Rosetta を上回る

FEX は 14/20 ワークロードで Rosetta より高速。
Interpreter startup (python3 0.32x, perl 0.28x) や package manager (dpkg 0.28x, dnf 0.43x) で圧倒的。
Compilation (gcc 0.60x, g++ 0.52x, make 0.57x) でも FEX が 1.7–1.9x 優位。

### 2. Rosetta は JIT-on-JIT ランタイムと rustc で優位

Rosetta は java (421ms vs 509ms)、node (311ms vs 449ms)、rustc (881ms vs 1,382ms) で FEX を上回る。
AOT バイナリ翻訳は JIT ランタイムの起動フェーズで有利。FEX の JIT-on-JIT オーバーヘッドが影響。
Python ecosystem: mypy は FEX wins (380ms vs 510ms)。django / ansible は Tie で拮抗。

### 3. JIT コードキャッシュが性能の鍵

FEX の JIT キャッシュは実行を重ねるほど高速化する。本ベンチマーク（`podman run --rm` で毎回新コンテナ）では
cold/warm 比 1.2–8x だが、同一コンテナ内での反復実行ではキャッシュが蓄積し **最大 16x** の改善を確認
（dnf check-update: 20.4s → 1.3s）。コードキャッシュはコンテナ単位で蓄積され、コンテナ削除で消失する（ephemeral）。

## Recommendations

| ユースケース | 推奨バックエンド | 理由 |
|-------------|:---------------:|------|
| **libkrun 環境** (GPU 利用等) | **FEX** | Rosetta 使用不可。FEX が QEMU の 18/20 で高速 |
| **Node.js ワークロード** | **Rosetta** > FEX > QEMU | Rosetta=311ms, FEX=449ms, QEMU=468ms |
| **Java ワークロード** | **Rosetta** > FEX > QEMU | Rosetta=421ms, FEX=509ms, QEMU=623ms |
| **.NET ワークロード** | **FEX** > Rosetta > QEMU | FEX=482ms, Rosetta=908ms — FEX が 1.9x 高速 |
| **Python ecosystem** | **FEX** ≈ Rosetta > QEMU | django/ansible/mypy 全て Tie — FEX と Rosetta が拮抗 |
| **Package manager 操作** | **FEX** > Rosetta > QEMU | 全 5 ワークロードで FEX 最速 |
| **Compilation ワークロード** | **FEX** > Rosetta > QEMU | gcc/g++/make で FEX 最速、rustc は Rosetta 最速 |
| **反復テスト / CI** | **FEX** (libkrun) | JIT キャッシュで反復実行ほど高速化 |

## Provider Comparison

| 特性 | Rosetta (applehv) | FEX-Emu (libkrun) | QEMU (libkrun) |
|------|:-----------------:|:------------------:|:--------------:|
| エミュレーション方式 | バイナリトランスレーション | JIT コンパイル | インタープリタ |
| コードキャッシュ | OS レベル (永続) | ファイルベース (コンテナ単位、ephemeral) | なし |
| Cold→Warm 改善 | なし (AOT 翻訳は即座) | **1.2–16x** ※ | なし |
| セットアップ | `enable-rosetta` + 再起動 | カスタム OS イメージ | 追加設定不要 |
| VM プロバイダ | applehv | libkrun | libkrun |
| GPU 利用 | ❌ なし | ✅ 対応 | ❌ なし |
| JIT-on-JIT 互換性 | ✅ 全 ok | ✅ 全 ok | ✅ 全 ok |

### エミュレーション方式の特徴

**Rosetta — バイナリトランスレーション (AOT)**
Apple が macOS 向けに提供する x86_64→ARM64 変換。実行前にバイナリ全体を事前変換し、変換結果を OS レベルでキャッシュする。初回実行から高速で、反復実行での変動が小さい。ただし Apple の Virtualization.framework (applehv) 専用であり、libkrun 環境では使用できない。

**FEX-Emu — JIT コンパイル**
実行時に x86_64 命令を ARM64 に JIT コンパイルする。初回実行は JIT コンパイルのオーバーヘッドで遅いが、コードキャッシュに変換結果を保存し、反復実行で劇的に高速化する (最大 16x)。コードキャッシュはコンテナ単位でファイルに保存され、同一コンテナ内の反復実行で蓄積される。コンテナ削除で消失する (ephemeral)。

**QEMU — インタープリタ**
x86_64 命令を1つずつ解釈実行する (qemu-user-static)。JIT コンパイルを行わないため、コードキャッシュの概念がなく、反復実行でも性能が変わらない。セットアップ不要で最も導入が容易だが、全バックエンド中で最も低速。

> **重要**: Rosetta は applehv プロバイダ必須。libkrun 環境（GPU 利用等）では使用不可。
> FEX-Emu は libkrun 環境での最適な x86_64 エミュレーション選択肢。

---

**Test Date**: April 2026 (FEX: 2026-04-08, Rosetta/QEMU: 2026-04-06)
**Environment**: Podman 6.0.0-dev, M1 Max macOS
**Methodology**: `bench/compare.sh` — 各ワークロードを `podman run --rm bash -c` で実行、全バックエンド **10 回実行 min** 採用
**Workloads**: 20 (7 categories: interpreter startup, package manager, compilation, Python ecosystem, build tools, system tools, JIT-on-JIT)
