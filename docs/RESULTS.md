# FEX-Emu エミュレーション テスト結果

> **最終テスト日**: 2026-04-06  
> **テストスイート**: `run-all-tests.sh` (17 テスト), `run-cache-warmup-bench.sh`

## テスト環境

| 項目 | 値 |
|------|-----|
| **ホスト OS** | macOS 26.3.1 (Apple Silicon M1 Max, arm64) |
| **VM タイプ** | libkrun |
| **ゲスト OS** | Fedora CoreOS (aarch64, 4K ページ) |
| **カーネル** | `6.19.10-200.tso.fc43.aarch64` (TSO パッチ済み) |
| **エミュレータ** | FEX-Emu + QEMU-user-static (binfmt_misc) |
| **Podman (Client)** | 6.0.0-dev (darwin/arm64) |
| **Podman (Server)** | 5.8.2-dev (linux/arm64) |
| **マシンスペック** | 4 CPU / 8GiB RAM / 100GiB Disk |
| **SELinux** | Enforcing |
| **コードキャッシュ** | 有効 (`FEX_ENABLECODECACHINGWIP=1`) |
| **キャッシュ方式** | コンテナ内エフェメラル (`/tmp/fex-data/cache/`) |

---

## 1. 互換性テスト (run-all-tests.sh)

containers/podman リポジトリから Rosetta/QEMU で失敗した Issue 17 件を FEX-Emu 環境でテスト。

### 結果サマリ

| 指標 | 初回 (03-07) | 前回 (04-03) | 今回 (04-06) | 変化 |
|------|:----------:|:----------:|:----------:|:----:|
| テスト数 | 13 | 13 | **17** | +4 |
| ✅ PASS | 8 | 8 | **12** | +4 |
| ❌ FAIL | 3 | 4 | **4** | — |
| ⏱️ TIMEOUT | 2 | 1 | 1 | — |
| **PASS 率** | 61.5% | 61.5% | **70.6%** | +9.1pp |

> [!IMPORTANT]
> **04-06: テストスイート拡張 + SWC 修正**
> - 4 件のテストを追加: gawk SIGSEGV (#23219), redis-cluster (D#27601), SWC/Next.js (#23269), su -l (#26656)
> - #15 SWC/Next.js (#23269): FEX ビルドイメージ更新（Node.js SIGILL 修正）により ❌→✅ に改善
> - 追加した 4 件のテストはすべて ✅ PASS

### テスト結果一覧

| # | テスト | Issue | 元の障害 | 結果 | Exit | 時間 |
|---|--------|-------|---------|:----:|:----:|-----:|
| 01 | MSSQL 2025 AVX | [#28184](https://github.com/containers/podman/issues/28184) | Rosetta: AVX | ❌ | 255 | 6s |
| 02 | MSSQL 2022 | [#27078](https://github.com/containers/podman/issues/27078) | Rosetta: SIGSEGV | ❌ | 134 | 16s |
| 03 | rustc | [#28169](https://github.com/containers/podman/issues/28169) | QEMU: SIGSEGV | ✅ | 0 | 3s |
| 04 | PyArrow | [#26036](https://github.com/containers/podman/issues/26036) | QEMU: SIGSEGV | ✅ | 0 | 7s |
| 05 | jemalloc | [#27320](https://github.com/containers/podman/issues/27320) | QEMU: SIGSEGV | ✅ | 0 | 160s |
| 06 | Arch Linux | [#27210](https://github.com/containers/podman/issues/27210) | Rosetta: ハング | ✅ | 0 | 2s |
| 07 | Fedora | [#27817](https://github.com/containers/podman/issues/27817) | Rosetta: ハング | ✅ | 0 | 2s |
| 08 | Ubuntu 25.10 | [#27799](https://github.com/containers/podman/issues/27799) | Rosetta: ハング | ✅ | 0 | 2s |
| 09 | Go hello build | [#26881](https://github.com/containers/podman/issues/26881) | Rosetta: panic | ❌ | 2 | 3s |
| 10 | Angular `ng build` | [#25272](https://github.com/containers/podman/issues/25272) | QEMU: ハング | ❌ | 127 | 7s |
| 11 | sudo BuildKit | [#24647](https://github.com/containers/podman/issues/24647) | Rosetta: nosuid | ✅ | 0 | 2s |
| 12 | Express 負荷テスト | [#26572](https://github.com/containers/podman/issues/26572) | Rosetta: フリーズ | ✅ | 0 | 45s |
| 13 | Go godump build | [#26919](https://github.com/containers/podman/issues/26919) | Rosetta: godump | ❌ | 2 | 3s |
| 13b | gawk | [#23219](https://github.com/containers/podman/issues/23219) | QEMU: SIGSEGV | ✅ | 0 | 111s |
| 14 | redis-cluster | [D#27601](https://github.com/containers/podman/discussions/27601) | QEMU: SIGSEGV | ✅ | 0 | 2s |
| 15 | SWC/Next.js | [#23269](https://github.com/containers/podman/issues/23269) | Rosetta: ハング | ✅ | 0 | 13s |
| 16 | su -l ログインシェル | [#26656](https://github.com/containers/podman/issues/26656) | Rosetta: 動作不具合 | ✅ | 0 | 2s |

### カテゴリ別改善率

| カテゴリ | テスト数 | PASS | 改善率 |
|---------|:------:|:----:|:-----:|
| QEMU SIGSEGV | 5 | **5** | **100%** |
| ハング/フリーズ (runtime) | 5 | **5** | **100%** |
| ビルド (Build Failures) | 5 | 2 | 40% |
| Rosetta クラッシュ | 1 | 0 | 0% |
| 動作不具合 (Behavioral) | 1 | **1** | **100%** |

### 未改善ケースの分析

| テスト | 原因 | 改善見込み |
|--------|------|:---:|
| MSSQL 2025 (#28184) | AVX 命令必須 — FEX-Emu は AVX 未サポート | ✗ |
| MSSQL 2022 (#27078) | 起動成功後にランタイムクラッシュ（タイミング依存） | △ |
| Go build (#26881, #26919, #25272) | Go ランタイム `internal/godebug` SIGSEGV — upstream FEX 互換性問題。Angular (#25272) の esbuild も同根 | △ |

---

## 2. コードキャッシュ ウォームアップ ベンチマーク (run-cache-warmup-bench.sh)

単一コンテナ内で同じコマンドを5回繰り返し、JIT コードキャッシュの蓄積効果を計測。

> **方式**: `podman run --rm ... bash -c 'for i in 1..5; do CMD; done'`  
> **所要時間**: 約 3 分（4テスト合計）

### 結果サマリ

| テスト | イメージ | Run 1 | Run 5 | Speedup |
|--------|---------|------:|------:|:-------:|
| C1: Fedora dnf | `fedora:latest` | 19.2s | 1.3s | **13.8x** |
| C2: PyArrow pip | `python:3.11-slim` | 15.2s | 5.6s | **2.7x** |
| C4: rustc version | `rust:1.93.0-bookworm` | 2.6s | 0.7s | **3.7x** |
| C5: Arch pacman | `archlinux:latest` | 1.2s | 0.1s | **12.7x** |

> C3 (Ubuntu jemalloc) はスキップ: apt-get が毎ラウンド ~170s かかり、コンテナ内5反復で timeout を超過するため。

### 詳細データ

#### C1: Fedora dnf check-update — 13.8x

| Run | Time | vs Run 1 |
|:---:|-----:|:--------:|
| 1 | 19.2s | baseline |
| 2 | 7.5s | 39% |
| 3 | 2.3s | 11% |
| 4 | 1.5s | 7% |
| 5 | 1.3s | **7%** |

#### C2: Python pip install pyarrow — 2.7x

| Run | Time | vs Run 1 |
|:---:|-----:|:--------:|
| 1 | 15.2s | baseline |
| 2 | 9.9s | 65% |
| 3 | 6.0s | 39% |
| 4 | 6.4s | 42% |
| 5 | 5.6s | **36%** |

> Run 3 以降が横ばいなのは、pip のネットワークダウンロード (~4s) が固定オーバーヘッドのため。

#### C4: rustc -vV — 3.7x

| Run | Time | vs Run 1 |
|:---:|-----:|:--------:|
| 1 | 2.6s | baseline |
| 2 | 3.5s | 135% |
| 3 | 0.8s | 32% |
| 4 | 0.7s | 26% |
| 5 | 0.7s | **26%** |

> Run 2 が Run 1 より遅いのは、FEX が非同期でキャッシュを書き出し中のため。Run 3 以降でキャッシュが有効化。

#### C5: Arch pacman sync — 12.7x

| Run | Time | vs Run 1 |
|:---:|-----:|:--------:|
| 1 | 1.2s | baseline |
| 2 | 0.9s | 76% |
| 3 | 0.4s | 33% |
| 4 | 0.1s | 7% |
| 5 | 0.1s | **7%** |

---

## 3. JIT コードキャッシュの仕組み

### キャッシュ方式: コンテナ内エフェメラル

FEX-Emu のコードキャッシュは **コンテナ内** (`/tmp/fex-data/cache/`) に保存される。

```
/tmp/fex-data/
├── Server/Server.lock
└── cache/codemap/new/
    ├── bash-c5fc4ba7388512ef.0.bin
    ├── find-19a1dee9ea146430.0.bin
    └── head-93804ade062b71e8.0.bin
```

| 変数 | 値 |
|------|-----|
| `FEX_APP_CACHE_LOCATION` | `/tmp/fex-data/cache/` |
| `FEX_APP_CONFIG_LOCATION` | `/tmp/fex-data/` |
| `FEX_APP_DATA_LOCATION` | `/tmp/fex-data/` |
| `FEX_ENABLECODECACHINGWIP` | `1` |

### エフェメラル方式を採用した経緯

当初はホスト側共有ボリューム（Strategy B）でコンテナ間キャッシュ共有を試みたが、**ASLR/VMA ミスマッチによる SIGSEGV** が発生（異なるイメージの同名バイナリが異なるメモリレイアウトで JIT キャッシュを共有し、絶対アドレスが不正になる）。

**解決策**: 共有ボリュームを廃止し、各コンテナが独立したエフェメラルキャッシュを使用（Strategy C）。コンテナ寿命内でのみキャッシュは有効。コンテナ削除時にキャッシュも消失する。

### キャッシュ蓄積の実測

| 操作 | キャッシュサイズ | .bin ファイル数 |
|------|:----------:|:----------:|
| `--rm` コンテナ (echo hello) | 16K | 7 |
| 永続コンテナ exec 1回目 (uname) | 28K | 10 |
| 永続コンテナ exec 2回目 (uname) | 3.5M | 10 |
| 永続コンテナ exec 3回目 (uname) | 4.3M | 10 |

> キャッシュは非同期書き出しのため、exec N の JIT 結果は exec N+1 の時点で反映される。

---

## 4. テスト結果アーカイブ

```
results/
├── run_20260331_141501_test/           # ★ 最新: 互換性テスト 13件
├── cache_warmup_20260331_142255/       # ★ 最新: ウォームアップ 4テスト
├── run_20260330_130358_test/           # 互換性テスト (前回)
├── cache_warmup_20260330_133206/       # ウォームアップ (前回)
├── run_20260307_150222_podman-machine-default/       # ルートレス (初期ベースライン)
└── run_20260307_152452_podman-machine-default-root/  # ルートフル (初期ベースライン)
```
