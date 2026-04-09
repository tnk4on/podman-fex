# Podman x86_64 エミュレーション障害: Rosetta/QEMU 未解決 Issue 一覧

> containers/podman リポジトリにおいて、Apple Silicon (macOS aarch64) 上で Rosetta または QEMU を使った x86_64 エミュレーションが失敗し、未解決のまま残っている Issue のうち、`podman run` または `podman build` コマンドが提示されているものを網羅的にリストする。

## 統計サマリ

| 項目 | 件数 |
|------|-----|
| **調査対象 Issue 総数** | 18 |
| OPEN | 14 |
| CLOSED (未根本解決) | 4 |
| **障害カテゴリ** | |
| 🔴 クラッシュ/SIGSEGV | 7 |
| 🟡 ハング/フリーズ | 5 |
| 🟠 ビルド失敗 | 4+1 |
| 🟣 動作不具合 | 1 |
| **テスト種別** | |
| `podman run` 即時テスト可能 | 12 |
| `podman build` テスト (Dockerfile 準備必要) | 5 |
| 負荷テスト (アプリ構築必要) | 1 |
| **原因エミュレータ** | |
| Rosetta 起因 | 9 |
| QEMU 起因 | 7 |
| BuildKit 固有 | 2 |

---

## 障害カテゴリ別 Issue 一覧

### 🔴 クラッシュ・SIGSEGV (7件)

#### 1. [#28184](https://github.com/containers/podman/issues/28184) — MSSQL 2025 AVX命令クラッシュ (Rosetta)
- **状態**: OPEN
- **症状**: Rosetta 2 が AVX/XSAVE 命令を正しくエミュレートできず、MSSQL 2025 コンテナが起動時に assertion failure
- **エラー**: `assertion failed [x86_avx_state_ptr->xsave_header.xfeatures == kSupportedXFeatureBits]`
- **再現コマンド**:
```bash
podman run -e 'ACCEPT_EULA=Y' -e 'SA_PASSWORD=Str0ng!Passw0rd' \
  -p 1433:1433 --platform linux/amd64 \
  mcr.microsoft.com/mssql/server:2025-latest
```

---

#### 2. [#27078](https://github.com/containers/podman/issues/27078) — MSSQL 2022 Segmentation Fault (Rosetta)
- **状態**: OPEN
- **症状**: MSSQL 2022 が Rosetta 有効環境で SIGSEGV。Docker Desktop/Rancher Desktop では動作する
- **エラー**: `Segmentation fault (core dumped)`
- **再現コマンド**:
```bash
podman run --memory=4096M -e "ACCEPT_EULA=Y" \
  -e "MSSQL_SA_PASSWORD=SecurePassword123$" \
  -p 1433:1433 --name sql2022 --rm -i \
  mcr.microsoft.com/mssql/server:2022-latest
```

---

#### 3. [#28169](https://github.com/containers/podman/issues/28169) — rustc SIGSEGV (QEMU)
- **状態**: OPEN
- **症状**: x86_64 Rust コンパイライメージが QEMU 下で SIGSEGV。realloc 中にクラッシュ
- **エラー**: `qemu: uncaught target signal 11 (Segmentation fault) - core dumped`
- **再現コマンド**:
```bash
podman run --rm --platform linux/amd64 \
  --entrypoint rustc \
  docker.io/library/rust:1.93.0-bookworm -vV
```

---

#### 4. [#26036](https://github.com/containers/podman/issues/26036) — PyArrow SIGSEGV (QEMU)
- **状態**: OPEN
- **症状**: Python PyArrow をインポートすると QEMU がクラッシュ。kill -9 でしか終了できない
- **エラー**: `qemu: uncaught target signal 11 (Segmentation fault) - core dumped`
- **再現コマンド**:
```bash
podman run --arch amd64 python:3.11-slim \
  bash -c 'pip install pyarrow==20.0.0; python -c "import pyarrow"'
```

---

#### 5. [#27320](https://github.com/containers/podman/issues/27320) — jemalloc SIGSEGV (QEMU)
- **状態**: OPEN
- **症状**: jemalloc をロードすると QEMU が SIGSEGV
- **エラー**: `qemu: uncaught target signal 11 (Segmentation fault) - core dumped`
- **再現コマンド**:
```bash
podman run -it --arch amd64 docker.io/library/ubuntu:latest
# コンテナ内で:
apt update && apt install libjemalloc2
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 /usr/bin/bash
```

---

#### 5b. [#23219](https://github.com/containers/podman/issues/23219) — gawk SIGSEGV (QEMU)
- **状態**: OPEN
- **症状**: OpenWrt imagebuilder コンテナで `gawk --version` が QEMU SIGSEGV。ファームウェアビルドシステムが破壊される
- **エラー**: `qemu: uncaught target signal 11 (Segmentation fault) - core dumped`
- **再現コマンド**:
```bash
podman run --rm --platform linux/amd64 debian:bookworm-slim \
  sh -c 'apt-get update -qq && apt-get install -y -qq gawk && gawk --version'
```

---

#### 5c. [D#27601](https://github.com/containers/podman/discussions/27601) — redis-cluster SIGSEGV (QEMU)
- **状態**: OPEN (Discussion)
- **症状**: `podman run duyquyen/redis-cluster` が M1 Mac で QEMU SIGSEGV。Apple HyperVisor + Rosetta / libkrun の両方で発生
- **エラー**: `qemu: uncaught target signal 11 (Segmentation fault) - core dumped`
- **再現コマンド**:
```bash
podman run --rm --platform linux/amd64 docker.io/duyquyen/redis-cluster redis-server --version
```

---

### 🟡 ハング・フリーズ (5件)

#### 6. [#27210](https://github.com/containers/podman/issues/27210) — Arch Linux ハング (Rosetta)
- **状態**: OPEN
- **症状**: amd64 版 Arch Linux コンテナでインタラクティブシェルがハング。Ctrl+C 不可
- **再現コマンド**:
```bash
podman run -it --arch amd64 archlinux
```

---

#### 7. [#26572](https://github.com/containers/podman/issues/26572) — Node.js/Express フリーズ (Rosetta)
- **状態**: OPEN
- **症状**: Rosetta 有効の linux/amd64 コンテナで Node.js Express アプリが負荷テスト中にフリーズ。QEMU に切り替えると安定動作
- **ワークアラウンド**: QEMU 使用
- **再現コマンド** (概要):
```bash
# 1. Rosetta有効化
# 2. linux/amd64 でExpressアプリのイメージをビルド
podman build --platform linux/amd64 -t express-app .
# 3. コンテナ起動後、並列HTTPリクエストを送信するとフリーズ
podman run --platform linux/amd64 express-app
```

---

#### 8. [#27817](https://github.com/containers/podman/issues/27817) — Fedora シェルハング (Rosetta) ⚠️ CLOSED
- **状態**: CLOSED
- **症状**: `podman run --platform linux/amd64 -it fedora sh` でハング。`uname -m` は動作する。Fedora 固有の問題
- **再現コマンド**:
```bash
podman run --rm --platform linux/amd64 -it fedora sh
```

---

#### 9. [#27799](https://github.com/containers/podman/issues/27799) — Ubuntu 25.10 ターミナルアタッチ不可 ⚠️ CLOSED
- **状態**: CLOSED
- **症状**: Ubuntu 25.10 の amd64 イメージで bash が開始せずスタック
- **再現コマンド**:
```bash
podman run -it --arch amd64 ubuntu:25.10 bash
```

---

#### 9b. [#23269](https://github.com/containers/podman/issues/23269) — Next.js ビルドハング / SWC (Rosetta/QEMU)
- **状態**: OPEN
- **症状**: `npm run build` (Next.js) が linux/amd64 コンテナで CPU を消費し続け永久にハング。SWC (Rust ベースの JS コンパイラ) のバイナリロード時に発生
- **ワークアラウンド**: ARM64 ネイティブイメージを使用
- **再現コマンド**:
```bash
podman run --rm --platform linux/amd64 node:20-slim \
  bash -c 'cd /tmp && npm init -y && npm install @swc/core && \
  node -e "const s = require(\"@swc/core\"); console.log(s.transformSync(\"const x: number = 1\", {jsc:{parser:{syntax:\"typescript\"}}}).code)"'
```

---

### 🟠 ビルド失敗 (4件)

#### 10. [#25272](https://github.com/containers/podman/issues/25272) — Angular ビルドハング (QEMU)
- **状態**: OPEN
- **症状**: `ng build` ステップで永久にスタック。arm64 ではビルド成功
- **再現コマンド**:
```bash
podman build --platform linux/amd64 -t ui -f ./ui/Dockerfile.dev . \
  --build-arg NG_APP_ENV=development
```

---

#### 11. [#26919](https://github.com/containers/podman/issues/26919) — Go ビルド godump (Rosetta)
- **状態**: OPEN
- **症状**: `podman build` 中の `go build` ステップで Go ランタイムが panic/godump
- **再現コマンド** (概要):
```bash
# Dockerfile内でgo buildするイメージをビルド
podman build .
```

---

#### 12. [#26881](https://github.com/containers/podman/issues/26881) — Podman 5.6.0 linux/amd64 ビルド&ランタイム崩壊 ⚠️ CLOSED
- **状態**: CLOSED (Podman 5.5.2 へのダウングレードで修正)
- **症状**: Podman 5.6.0 で linux/amd64 の Go イメージビルドと実行が panic
- **再現コマンド**:
```bash
# Dockerfile を用意:
# FROM --platform=linux/amd64 golang:1.24-alpine
# ... go build ...
podman build .
```

---

#### 13. [#24647](https://github.com/containers/podman/issues/24647) — sudo が Rosetta + BuildKit で動作しない
- **状態**: OPEN
- **症状**: BuildKit + Rosetta 2 環境で x86_64 コンテナ内の `sudo` が `nosuid` エラー
- **エラー**: `sudo: effective uid is not 0, is /usr/bin/sudo on a file system with the 'nosuid' option set`
- **再現コマンド**:
```bash
# Dockerfile:
# FROM alpine
# RUN apk add shadow sudo
# RUN echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers
# RUN useradd --create-home --non-unique --uid 1000 --groups wheel user
# USER 1000
# RUN sudo /bin/ls
docker buildx build --platform=linux/x86_64 . --load
# (podman build --platform=linux/x86_64 . では動作する — BuildKit固有)
```

---

#### 14. [#24000](https://github.com/containers/podman/issues/24000) — buildkit_qemu_emulator SELinux エラー
- **状態**: OPEN
- **症状**: BuildKit 経由で amd64 ビルドすると SELinux xattr エラー
- **エラー**: `failed to set xattr "security.selinux": operation not supported`
- **再現コマンド**:
```bash
DOCKER_BUILDKIT=1 docker build . --tag test:latest \
  --platform=linux/amd64 -f Dockerfile --load
```

---

### 🟣 動作不具合 (1件)

#### 15. [#26656](https://github.com/containers/podman/issues/26656) — su -l がログインシェルにならない (Rosetta)
- **状態**: OPEN
- **症状**: Apple Silicon macOS + Rosetta で `su -l` がログインシェルを開始しない。Bash が "Not login shell" と報告し、IBM DB2 等 `su` に依存するコンテナが動作しない
- **再現コマンド**:
```bash
podman run --rm --platform linux/amd64 registry.access.redhat.com/ubi8:latest \
  sh -c 'useradd appuser && su -l appuser -c "shopt -q login_shell && echo Login_shell || echo Not_login_shell"'
```

---

## FEX-Emu テストマトリクス

以下は、FEX-Emu で改善が見込めるかどうかをテストするためのコマンド一覧。`podman run` は `--arch amd64` に統一。

| # | Issue | カテゴリ | テストコマンド | 期待される改善 |
|---|-------|---------|-------------|-------------|
| 1 | #28184 | MSSQL 2025 AVX | `podman run -e 'ACCEPT_EULA=Y' -e 'SA_PASSWORD=Str0ng!Passw0rd' -p 1433:1433 --platform linux/amd64 mcr.microsoft.com/mssql/server:2025-latest` | FEX-Emu のAVXサポート次第 |
| 2 | #27078 | MSSQL 2022 SIGSEGV | `podman run --memory=4096M -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=SecurePassword123$" -p 1433:1433 --rm mcr.microsoft.com/mssql/server:2022-latest` | QEMU/Rosettaのメモリ管理の問題なら改善の可能性あり |
| 3 | #28169 | rustc SIGSEGV | `podman run --rm --platform linux/amd64 --entrypoint rustc docker.io/library/rust:1.93.0-bookworm -vV` | realloc 実装の問題なら改善の可能性あり |
| 4 | #26036 | PyArrow SIGSEGV | `podman run --arch amd64 python:3.11-slim bash -c 'pip install pyarrow==20.0.0; python -c "import pyarrow"'` | 命令エミュレーション次第 |
| 5 | #27320 | jemalloc SIGSEGV | `podman run -it --arch amd64 ubuntu:latest` → `apt install libjemalloc2; LD_PRELOAD=... bash` | メモリアロケータの互換性次第 |
| 5b | #23219 | gawk SIGSEGV | `podman run --rm --platform linux/amd64 debian:bookworm-slim sh -c 'apt-get update && apt-get install -y gawk && gawk --version'` | 命令エミュレーション次第 |
| 5c | D#27601 | redis-cluster SIGSEGV | `podman run --rm --platform linux/amd64 docker.io/duyquyen/redis-cluster redis-server --version` | jemalloc 関連なら改善の可能性あり |
| 6 | #27210 | Arch Linux ハング | `podman run -it --arch amd64 archlinux` | ターミナルI/Oの問題なら改善の可能性高い |
| 7 | #26572 | Node.js フリーズ | Express アプリのビルド＆負荷テスト | スレッドスケジューリングの問題なら改善の可能性あり |
| 8 | #27817 | Fedora ハング | `podman run --rm --platform linux/amd64 -it fedora sh` | CLOSED だがテスト価値あり |
| 9 | #27799 | Ubuntu ハング | `podman run -it --arch amd64 ubuntu:25.10 bash` | CLOSED だがテスト価値あり |
| 9b | #23269 | SWC/Next.js ハング | `podman run --rm --platform linux/amd64 node:20-slim bash -c 'npm install @swc/core && node -e ...'` | ✅ FEX ビルドイメージ更新で修正済み |
| 10 | #25272 | Angular ビルドハング | `podman build --platform linux/amd64` (Angular) | CPUバウンドビルドの問題なら改善の可能性あり |
| 11 | #26919 | Go ビルド godump | `podman build` (Go microservice) | Goランタイムの互換性次第 |
| 12 | #24647 | sudo nosuid | BuildKit + x86_64 `sudo` | binfmt_misc の違いによる可能性 |
| 13 | #24000 | SELinux xattr | BuildKit + amd64 ビルド | SELinux設定の問題でFEXとは無関係の可能性 |
| 14 | #26881 | Go build panic | `podman build` (Go hello world) | Go 1.24+ FIPS/AES の問題 |
| 15 | #26656 | su -l 動作不具合 | `podman run --rm --platform linux/amd64 ubi8 sh -c 'useradd appuser && su -l appuser -c ...'` | syscall エミュレーション次第 |

## FEX-Emu テスト実行計画

テストはワークスペース内の専用ディレクトリ `fex-emu-tests/` に集約する。

```
fex-emu-tests/
├── run-all-tests.sh          # 全テスト一括実行スクリプト
├── run/                      # podman run テスト
│   ├── 01-mssql-2025.sh      # #28184
│   ├── 02-mssql-2022.sh      # #27078
│   ├── 03-rustc.sh           # #28169
│   ├── 04-pyarrow.sh         # #26036
│   ├── 05-jemalloc.sh        # #27320
│   ├── 06-archlinux.sh       # #27210
│   ├── 07-fedora.sh          # #27817
│   ├── 08-ubuntu.sh          # #27799
│   ├── 12-nodejs-express.sh  # #26572 — Express 負荷テスト
│   ├── 13b-gawk.sh           # #23219 — gawk SIGSEGV
│   ├── 14-redis-cluster.sh   # D#27601 — redis-cluster SIGSEGV
│   ├── 15-swc-nextjs.sh      # #23269 — SWC/Next.js
│   └── 16-su-login-shell.sh  # #26656 — su -l 動作不具合
├── build/                    # podman build テスト
│   ├── 09-go-hello/          # #26881 — Go ビルド
│   │   ├── Dockerfile
│   │   ├── main.go
│   │   └── go.mod
│   ├── 10-angular/           # #25272 — Angular ビルド (簡易再現)
│   │   └── Dockerfile
│   ├── 11-sudo-buildkit/     # #24647 — sudo + BuildKit
│   │   └── Dockerfile
│   ├── 12-nodejs-express/    # #26572 — Node.js Express + 負荷テスト
│   │   ├── Dockerfile
│   │   ├── server.js
│   │   └── package.json
│   └── 13-go-build/          # #26919 — Go ビルド godump
│       ├── Dockerfile
│       ├── main.go
│       └── go.mod
└── results/                  # テスト結果出力
    └── .gitkeep
```

## 備考

- **CLOSED されたイシュー** (#27817, #27799, #26881) も、根本的なエミュレーション問題が解決されていない場合があるためテスト対象に含めている
- **BuildKit 固有の問題** (#24647, #24000) は FEX-Emu の binfmt_misc 登録方法によって挙動が変わる可能性がある
- **Node.js フリーズ** (#26572) は負荷テスト環境の構築が必要だが、簡易 Express サーバーで再現を試みる
- **Angular ビルド** (#25272) は `ng build` のハングを再現するため、最小限の Angular プロジェクトを作成する
- **#24000 (SELinux xattr)** は FEX-Emu とは無関係の SELinux 設定問題のため、テスト対象外とする
- **gawk (#23219)** は元 Issue が OpenWrt imagebuilder (403 Forbidden) のため、Debian bookworm + apt-get install gawk で代替テスト
- **redis-cluster (D#27601)** は Discussion であり Issue ではないが、QEMU SIGSEGV の再現として有用
- **SWC/Next.js (#23269)** は FEX ビルドイメージ更新 (2026-04-06) で修正済み
- **su -l (#26656)** は Rosetta 固有の動作不具合で、FEX-Emu では正しくログインシェルが開始される
