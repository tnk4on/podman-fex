# Cross-Backend Benchmark: FEX-Emu vs QEMU vs Rosetta

## Executive Summary

Apple Silicon (M1 Max) での x86_64 コンテナエミュレーション性能を 3 バックエンドで比較。
20 の実用的ワークロードを 7 カテゴリに分類し、min 値で評価。

| Backend | VM Provider | Emulation | Interpreter Startup | Package Mgr | Compilation |
|---------|-------------|-----------|:---:|:---:|:---:|
| **FEX-Emu** | libkrun | JIT | 17–129ms | 23–159ms | 201–1,490ms |
| **QEMU** | libkrun | qemu-user-static | 68–577ms | 131–669ms | 529–4,203ms |
| **Rosetta** | applehv | Binary translation | 54–225ms | 71–281ms | 316–1,322ms |

**結論**:
- **FEX は 18/20 ワークロードで QEMU より高速** — 全カテゴリで優位
- **FEX vs Rosetta: 13 勝 / 4 引 / 3 敗** — Interpreter startup・Package manager・Compilation で FEX 圧倒的優位
- **Rosetta は rustc / java / node で FEX より高速** — AOT 翻訳が JIT ランタイムに有利
- **libkrun 環境では FEX が唯一の高速エミュレーション選択肢** — Rosetta は applehv 専用のため使用不可

## Environment

| Item | Detail |
|------|--------|
| Host | Apple M1 Max, macOS 26.3.1 |
| Podman | 6.0.0-dev (`/opt/podman/bin/podman`) |
| FEX VM | libkrun, 4 CPU / 8 GiB, Fedora CoreOS + FEX-Emu (`quay.io/tnk4on/machine-os:5.8`) |
| FEX Build | FEX-2603, `-DCMAKE_BUILD_TYPE=Release`, static-pie |
| QEMU VM | libkrun, 4 CPU / 8 GiB, Fedora CoreOS (default image, qemu-user-static) |
| Rosetta VM | applehv, 4 CPU / 8 GiB, Fedora CoreOS (default image, Rosetta binary translation) |
| Date | 2026-04-06 |

> **測定方式**: 各ワークロードを `podman run --rm bash -c` で実行。全バックエンド 10 回実行で min を取得。OCI hook が `FEX_APP_*` 環境変数を設定し、JIT コードキャッシュが機能する。

## Full Results

20 ワークロード × 3 バックエンド。**min 値**（最小値）を採用。**Winner** = fastest backend (Tie = ±10%)。

### Category 1: Interpreter Startup

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 1 | `python3 -c print(42)` | **43** | 390 | 116 | **FEX** | 0.37x |
| 2 | `perl -e print` | **17** | 68 | 54 | **FEX** | 0.31x |
| 3 | `ruby -e puts` | **129** | 577 | 225 | **FEX** | 0.57x |

> FEX が全 3 ワークロードで最速。Rosetta も QEMU の 2–3x 高速だが、FEX はその Rosetta をさらに 2–3x 上回る。

### Category 2: Package Manager Operations

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 4 | `rpm -V bash` | **88** | 397 | 187 | **FEX** | 0.47x |
| 5 | `rpm -qa \| wc -l` | **159** | 604 | 222 | **FEX** | 0.72x |
| 6 | `dpkg -l \| wc -l` | **23** | 131 | 71 | **FEX** | 0.32x |
| 7 | `pacman -Sy` | **51** | 186 | 113 | **FEX** | 0.45x |
| 8 | `dnf repoquery --installed` | **149** | 669 | 281 | **FEX** | 0.53x |

> FEX が全 5 ワークロードで最速。Rosetta も QEMU の 2–2.5x 高速だが、FEX は Rosettaをさらに 1.4–3.2x 上回る。

### Category 3: Compilation

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 9 | `gcc hello.c` | **201** | 529 | 316 | **FEX** | 0.64x |
| 10 | `g++ -O2 hello.cpp (STL)` | **823** | 4,203 | 1,322 | **FEX** | 0.62x |
| 11 | `make hello` | **227** | 567 | 345 | **FEX** | 0.66x |

> FEX が全 3 ワークロードで最速。Rosetta は QEMU の 1.6–3.2x 高速だが、FEX は Rosetta をさらに 1.5–1.6x 上回る。

### Category 4: Python Ecosystem

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 12 | `django manage.py check` | 489 | 1,706 | **463** | Tie | 1.06x |
| 13 | `ansible localhost ping` | 1,769 | 6,605 | **1,724** | Tie | 1.03x |
| 14 | `mypy type-check` | **477** | 1,611 | 510 | Tie | 0.94x |

> FEX と Rosetta が拮抗。django (FEX=489 vs Rosetta=463)、ansible (FEX=1769 vs Rosetta=1724) は Rosetta がわずかに速いが±10% 以内で Tie。mypy は FEX が 6% 優位で Tie。

### Category 5: Build Tools

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 15 | `perl regex 10k` | **26** | 99 | 67 | **FEX** | 0.39x |
| 16 | `rustc compile hello` | 1,490 | ~~438~~ | **881** | **Rosetta** | 1.69x |

> perl regex: FEX が Rosetta の 2.6x 高速。rustc: Rosetta が FEX の 1.69x 高速。QEMU は SIGSEGV (exit 139) で失敗。

### Category 6: System Tools

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|
| 17 | `Rscript sum(1:1000)` | 576 | 1,318 | 612 | Tie | 0.94x |

> FEX と Rosetta がほぼ同等 (6% 差、Tie に近いが FEX がわずかに優位)。QEMU は両者の 2.2x 遅い。

### Category 7: JIT-on-JIT Runtimes

| # | Workload | FEX (ms) | QEMU (ms) | Rosetta (ms) | Winner | FEX/Rosetta | Notes |
|--:|----------|--------:|---------:|------------:|:------:|:-----------:|:------|
| 18 | `java HelloWorld` | 526 | 623 | **421** | **Rosetta** | 1.25x |
| 19 | `node -e console.log(42)` | 461 | 468 | **311** | **Rosetta** | 1.48x |
| 20 | `dotnet --info` | **561** | 1,682 | 908 | **FEX** | 0.62x |

> java と node で Rosetta が FEX より高速。AOT バイナリ翻訳が JIT-on-JIT ランタイムに有利。
> dotnet は FEX が Rosetta の 1.6x 高速。

## Win/Loss Summary

### FEX vs Rosetta

| Result | Count | Workloads |
|--------|:-----:|-----------|
| **FEX wins** | **13** | python3, perl, ruby, rpm-V, rpm-qa, dpkg, pacman, dnf, gcc, g++ STL, make, perl regex, dotnet |
| **Tie** (±10%) | **4** | django, ansible, mypy, Rscript |
| **Rosetta wins** | **3** | rustc, java, node |

### FEX vs QEMU

| Result | Count | Workloads |
|--------|:-----:|-----------|
| **FEX wins** | **18** | python3, perl, ruby, rpm-V, rpm-qa, dpkg, pacman, dnf, gcc, g++ STL, make, django, ansible, mypy, perl regex, Rscript, java, dotnet |
| **Tie** | **1** | node (FEX=461, QEMU=468) |
| **QEMU wins** | **0** | — |
| **N/A** | **1** | rustc (QEMU: SIGSEGV) |

## Key Insights

### 1. FEX が大半のワークロードで Rosetta を上回る

FEX は 13/20 ワークロードで Rosetta より高速。
Interpreter startup (python3 0.37x, perl 0.31x) や package manager (dpkg 0.32x, dnf 0.53x) で圧倒的。
Compilation (gcc 0.64x, g++ 0.62x, make 0.66x) でも FEX が 1.5–1.6x 優位。

### 2. Rosetta は JIT-on-JIT ランタイムと rustc で優位

Rosetta は java (421ms vs 526ms)、node (311ms vs 461ms)、rustc (881ms vs 1,490ms) で FEX を上回る。
AOT バイナリ翻訳は JIT ランタイムの起動フェーズで有利。FEX の JIT-on-JIT オーバーヘッドが影響。
Python ecosystem (django, ansible, mypy) は Tie で、FEX と Rosetta が拮抗。

### 3. JIT コードキャッシュが性能の鍵

FEX の JIT キャッシュは実行を重ねるほど高速化する。Run 1–3 は JIT コンパイルで 2–6x 遅いが、
Run 4 以降はキャッシュ済みコードで高速実行される。コードキャッシュはコンテナ単位で蓄積され、
コンテナ削除で消失する（ephemeral）。本ベンチマーク（10 回実行 min）はキャッシュ蓄積過程を含む。

## Recommendations

| ユースケース | 推奨バックエンド | 理由 |
|-------------|:---------------:|------|
| **libkrun 環境** (GPU 利用等) | **FEX** | Rosetta 使用不可。FEX が QEMU の 18/20 で高速 |
| **Node.js ワークロード** | **Rosetta** > FEX > QEMU | Rosetta=311ms, FEX=461ms, QEMU=468ms |
| **Java ワークロード** | **Rosetta** > FEX > QEMU | Rosetta=421ms, FEX=526ms, QEMU=623ms |
| **.NET ワークロード** | **FEX** > Rosetta > QEMU | FEX=561ms, Rosetta=908ms — FEX が 1.6x 高速 |
| **Python ecosystem** | **FEX** ≈ Rosetta > QEMU | django/ansible/mypy 全て Tie — FEX と Rosetta が拮抗 |
| **Package manager 操作** | **FEX** > Rosetta > QEMU | 全 5 ワークロードで FEX 最速 |
| **Compilation ワークロード** | **FEX** > Rosetta > QEMU | gcc/g++/make で FEX 最速、rustc は Rosetta 最速 |
| **反復テスト / CI** | **FEX** (libkrun) | JIT キャッシュで反復実行ほど高速化 |

## Provider Comparison

| 特性 | Rosetta (applehv) | FEX-Emu (libkrun) | QEMU (libkrun) |
|------|:-----------------:|:------------------:|:--------------:|
| エミュレーション方式 | バイナリトランスレーション | JIT コンパイル | インタープリタ |
| コードキャッシュ | OS レベル (永続) | ファイルベース (コンテナ単位、ephemeral) | なし |
| Cold→Warm 改善 | なし (AOT 翻訳は即座) | **2–6x** | なし |
| セットアップ | `enable-rosetta` + 再起動 | カスタム OS イメージ | 追加設定不要 |
| VM プロバイダ | applehv 必須 | libkrun 必須 | libkrun |
| GPU パススルー | ❌ なし | ✅ 対応 | ❌ なし |
| JIT-on-JIT 互換性 | ✅ 全 ok | ✅ 全 ok | rustc: exit 139 |
| Hardware TSO | N/A | ✅ ACTLR_EL1 | N/A |

### エミュレーション方式の特徴

**Rosetta — バイナリトランスレーション (AOT)**
Apple が macOS 向けに提供する x86_64→ARM64 変換。実行前にバイナリ全体を事前変換し、変換結果を OS レベルでキャッシュする。初回実行から高速で、反復実行での変動が小さい。ただし Apple の Virtualization.framework (applehv) 専用であり、libkrun 環境では使用できない。

**FEX-Emu — JIT コンパイル**
実行時に x86_64 命令を ARM64 に JIT コンパイルする。初回実行は JIT コンパイルのオーバーヘッドで遅いが、コードキャッシュに変換結果を保存し、2回目以降の実行で劇的に高速化する (2–6x)。コードキャッシュはコンテナ単位でファイルに保存され、同一コンテナ内の反復実行で蓄積される。コンテナ削除で消失する (ephemeral)。

**QEMU — インタープリタ**
x86_64 命令を1つずつ解釈実行する (qemu-user-static)。JIT コンパイルを行わないため、コードキャッシュの概念がなく、反復実行でも性能が変わらない。セットアップ不要で最も導入が容易だが、全バックエンド中で最も低速。

> **重要**: Rosetta は applehv プロバイダ必須。libkrun 環境（GPU 利用等）では使用不可。
> FEX-Emu は libkrun 環境での最適な x86_64 エミュレーション選択肢。

---

**Test Date**: April 2026
**Environment**: Podman 6.0.0-dev, M1 Max macOS
**Methodology**: `bench-compare.sh` — 各ワークロードを `podman run --rm bash -c` で実行、全バックエンド **10 回実行 min** 採用
**Workloads**: 20 (7 categories: interpreter startup, package manager, compilation, Python ecosystem, build tools, system tools, JIT-on-JIT)
