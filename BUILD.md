# FEX 対応ブランチのビルド手順

このドキュメントでは、FEX-Emu 対応の Podman Machine OS イメージをソースからビルドする手順を説明します。

> [!NOTE]
> ユーザーとしてイメージを使うだけなら、ビルドは不要です。[README.md](README.md) の Quick Start を参照してください。

---

## 目次

1. [アーキテクチャ概要](#アーキテクチャ概要)
2. [前提条件](#前提条件)
3. [リポジトリ構成](#リポジトリ構成)
4. [Containerfile の構造](#containerfile-の構造)
5. [ビルド手順](#ビルド手順)
6. [レジストリへの Push](#レジストリへの-push)
7. [テスト](#テスト)
8. [トラブルシューティング](#トラブルシューティング)

---

## アーキテクチャ概要

イメージは **3 ステージの multi-stage Containerfile** でビルドされます:

```
┌─────────────────────────────────────────────────────────────┐
│  Stage 1: fex-builder (fedora:43)                           │
│  ・tnk4on/FEX fex-emu ブランチをクローン                       │
│  ・cmake + ninja で static-pie ビルド                         │
│  → FEXInterpreter, FEXServer, FEXOfflineCompiler             │
├─────────────────────────────────────────────────────────────┤
│  Stage 2: podman-builder (fedora:43)                        │
│  ・tnk4on/podman fex-emu ブランチをクローン                     │
│  ・make podman でビルド                                       │
│  → io.podman.image.arch annotation 付き podman バイナリ       │
├─────────────────────────────────────────────────────────────┤
│  Stage 3: Final OS (fedora-coreos:stable)                    │
│  ・upstream の build_common.sh を実行                          │
│  ・パッチ済み Podman を配置                                    │
│  ・fex-emu RPM + RootFS をインストール                         │
│  ・QEMU x86/x86_64 binfmt を削除（FEX に置換）                │
│  ・FEX static-pie バイナリで RPM 版を上書き                    │
│  ・OCI hook スクリプト・JSON を配置                            │
│  ・FEX activation systemd service を配置                      │
│  → podman-machine.aarch64.applehv.raw.zst                    │
└─────────────────────────────────────────────────────────────┘
```

### コンポーネントの役割

| コンポーネント | 説明 |
|---|---|
| **FEXInterpreter** | x86/x86_64 ELF バイナリを JIT エミュレーションする本体 (static-pie) |
| **FEXServer** | コードキャッシュの管理デーモン。各コンテナ内で FEXInterpreter が `fork+execvp` で自動起動し、AF_UNIX ソケットでローカル IPC 通信する |
| **パッチ済み Podman** | `io.podman.image.arch` アノテーションを自動付与し、OCI hook でアーキテクチャ別フィルタリングを実現 |
| **OCI hook** | `fex-emu-hook.sh` — amd64 コンテナにのみ FEX バイナリのバインドマウントを注入（ARM64 コンテナはゼロオーバーヘッド） |
| **containers.conf** | `FEX_APP_*` 環境変数を全コンテナに設定。OCI spec に反映されるため `podman exec` にも継承される |
| **fex-activation.service** | VM 初回起動時に EROFS ループマウント、binfmt 登録、containers.conf 設定を実行 |

---

## 前提条件

| 項目 | 要件 |
|---|---|
| **ビルドホスト** | Fedora 43 ARM64 (aarch64) — `ssh fedora43arm-root` |
| **root 権限** | osbuild にルート権限が必要 |
| **ディスク容量** | 最低 50GB の空き容量 |
| **必須パッケージ** | podman, buildah, rpm-ostree, osbuild (Fedora 43 標準) |
| **ネットワーク** | GitHub (リポジトリ clone), Quay.io (ベースイメージ pull) |

> [!IMPORTANT]
> macOS 上ではビルドできません。ARM64 Linux ビルドホストが必要です。

---

## リポジトリ構成

3 つのリポジトリの `fex-emu` ブランチに変更があります:

| リポジトリ | ブランチ | 変更内容 |
|---|---|---|
| **[tnk4on/podman-machine-os](https://github.com/tnk4on/podman-machine-os/tree/fex-emu)** | `fex-emu` | Containerfile に FEX ビルドステージ追加、OCI hook、activation service |
| **[tnk4on/FEX](https://github.com/tnk4on/FEX/tree/fex-emu)** | `fex-emu` | コンテナ向けコードキャッシュパス解決、ProcessPipe バッファ修正、personality() 修正 |
| **[tnk4on/podman](https://github.com/tnk4on/podman/tree/fex-emu)** | `fex-emu` | `io.podman.image.arch` アノテーション自動注入、FEX コードキャッシュ設定 (v5.8 ベース) |

### Containerfile が参照するリポジトリ

Containerfile 内で直接 clone されるのは 2 つ:

```dockerfile
# Stage 1: FEX
ARG FEX_BRANCH=fex-emu
RUN git clone --depth 1 --branch ${FEX_BRANCH} \
    https://github.com/tnk4on/FEX.git /src/FEX

# Stage 2: Podman
ARG PODMAN_REPO=https://github.com/tnk4on/podman.git
ARG PODMAN_BRANCH=fex-emu
RUN git clone --depth 1 --branch ${PODMAN_BRANCH} ${PODMAN_REPO} /src/podman
```

> krunkit と libkrun は macOS 側のコンポーネントであり、イメージビルドには含まれません。

---

## Containerfile の構造

### Stage 1: FEX ビルダー

Fedora 43 上で FEX-Emu を static-pie バイナリとしてビルドします:

- **ベースイメージ**: `fedora:43`
- **ビルドツール**: clang, lld, cmake, ninja
- **ソース**: `tnk4on/FEX` `fex-emu` ブランチ（パッチはブランチに統合済み）
- **CMake オプション**:
  - `-DCMAKE_BUILD_TYPE=Release` (**必須** — 未指定だと最適化なしで性能 2〜3 倍劣化)
  - `-DBUILD_SHARED_LIBS=OFF` — static-pie ビルド
  - `-DBUILD_THUNKS=OFF` `-DBUILD_TESTS=OFF` `-DBUILD_FEXCONFIG=OFF`
  - `-DENABLE_JEMALLOC=ON`
  - `-DCMAKE_EXE_LINKER_FLAGS=-static-pie`
- **出力**: `FEXInterpreter`, `FEXServer`, `FEXOfflineCompiler`

### Stage 2: Podman ビルダー

パッチ済み Podman をビルドします:

- **ベースイメージ**: `fedora:43`
- **ソース**: `tnk4on/podman` `fex-emu` ブランチ (v5.8 ベース)
- **変更点**: すべてのコンテナに `io.podman.image.arch` アノテーションを自動付与
- **ビルドコマンド**: `make podman BUILDTAGS="seccomp selinux systemd exclude_graphdriver_btrfs cni"`

### Stage 3: Final OS イメージ

Fedora CoreOS ベースイメージに全コンポーネントを統合:

1. `build_common.sh` 実行 (upstream 共通ビルドステップ)
2. パッチ済み Podman を `/usr/bin/podman` に配置
3. FEX-Emu RPM パッケージインストール (`fex-emu`, `fex-emu-rootfs-fedora`)
4. QEMU x86/x86_64 binfmt 設定を削除 (FEX に置換、他アーキの QEMU は保持)
5. `fex-activation.service` / `fex-activation.sh` 配置
6. OCI hook (`fex-emu-hook.sh`, `fex-emu-hook.json`) 配置
7. FEX static-pie バイナリを Stage 1 からコピー (RPM の動的バイナリを置換)

> すべての FEX 関連ステップは `if [ "$(uname -m)" = "aarch64" ]` で条件分岐しており、x86_64 ビルドでは自動的にスキップされます。

---

## ビルド手順

### Step 1: ビルドサーバーにログイン

```bash
ssh fedora43arm-root
```

### Step 2: リポジトリ最新化

```bash
cd /root/podman-machine-os
git fetch origin
git checkout fex-emu
git submodule update --init

# build.sh / util.sh / gather.sh を upstream v5.8 にリセット
# (fex-emu ブランチの変更は Containerfile とその関連ファイルのみ)
git checkout origin/v5.8 -- build.sh util.sh gather.sh
echo "build.sh/util.sh/gather.sh reset to origin/v5.8"
```

### Step 3: ビルド前の準備

```bash
# SELinux を一時的に permissive に変更 (osbuild が必要とする)
setenforce 0

# 古い出力ファイルを削除 (zstd の上書き確認を防止)
rm -f /root/podman-machine-os/outdir/*.zst /root/podman-machine-os/outdir/*.tar

# ディスク領域の回収
fstrim -v /

# OSBuild キャッシュの削除 (数 GB 消費するため)
rm -rf /var/cache/osbuild* /var/tmp/osbuild* 2>/dev/null
echo "OSBuild cache cleared"

# TMPDIR を設定 (/tmp はサイズ不足)
export TMPDIR=/var/tmp
```

### Step 4: ビルド実行

`build.sh` は upstream と同一に保ち、`sed | bash` で一時的に applehv のみビルドします:

```bash
cd /root/podman-machine-os
sed -e '/^PLATFORMS=/c\PLATFORMS="applehv"' \
    -e '/^(/,/^) &>/d' \
    -e '/trap.*WSL/d' \
    -e '/wait -n/d' \
    build.sh | bash
```

**sed パターンの解説:**

| パターン | 目的 |
|---|---|
| `/^PLATFORMS=/c\PLATFORMS="applehv"` | PLATFORMS を applehv のみに変更 |
| `/^(/,/^) &>/d` | WSL ビルドのサブシェルブロックを削除 |
| `/trap.*WSL/d` | WSL ジョブの trap 行を削除 |
| `/wait -n/d` | WSL ジョブの wait を削除 |

> [!IMPORTANT]
> `build.sh` 自体は変更しません。`sed | bash` でパイプ実行するため、upstream 互換を維持できます。

### Step 5: 出力確認

```bash
ls -lh /root/podman-machine-os/outdir/podman-machine.aarch64.applehv.raw.zst
```

期待される出力: `podman-machine.aarch64.applehv.raw.zst` (約 2〜3 GB)

---

## レジストリへの Push

### ローカルレジストリ (開発用)

ビルドサーバー上で HTTP レジストリが稼働しています (`192.168.1.28:5000`):

```bash
ssh fedora43arm-root 'cd /root/podman-machine-os && source util.sh && \
  OUTDIR=outdir && \
  TAG="192.168.1.28:5000/podman/machine-os:5.8" && \
  DISK_IMG="${OUTDIR}/podman-machine.aarch64.applehv.raw.zst" && \
  buildah manifest rm "${TAG}" 2>/dev/null; \
  buildah manifest create "${TAG}" && \
  buildah manifest add --arch arm64 "${TAG}" \
    "containers-storage:${FULL_IMAGE_NAME_ARCH}" && \
  buildah manifest add --artifact --artifact-type="" \
    --os=linux --arch=aarch64 --annotation "disktype=applehv" \
    "${TAG}" "${DISK_IMG}" && \
  buildah manifest push --all --tls-verify=false \
    "${TAG}" "docker://${TAG}" && \
  echo "✅ Pushed to ${TAG}"'
```

### Quay.io (公開用)

```bash
ssh fedora43arm-root 'cd /root/podman-machine-os && source util.sh && \
  OUTDIR=outdir && \
  QUAY_TAG="quay.io/tnk4on/machine-os:5.8" && \
  DISK_IMG="${OUTDIR}/podman-machine.aarch64.applehv.raw.zst" && \
  buildah manifest rm "${QUAY_TAG}" 2>/dev/null; \
  buildah manifest create "${QUAY_TAG}" && \
  buildah manifest add --arch arm64 "${QUAY_TAG}" \
    "containers-storage:${FULL_IMAGE_NAME_ARCH}" && \
  buildah manifest add --artifact --artifact-type="" \
    --os=linux --arch=aarch64 --annotation "disktype=applehv" \
    "${QUAY_TAG}" "${DISK_IMG}" && \
  buildah manifest push --all \
    "${QUAY_TAG}" "docker://${QUAY_TAG}" && \
  echo "✅ Pushed to ${QUAY_TAG}"'
```

### OCI Artifact の構造

レジストリに push される manifest は upstream の `gather.sh` と同等の構造です:

```
manifest index
├── arm64 ostree container image (rpm-ostree rechunk 済み)
└── applehv disk artifact (podman-machine.aarch64.applehv.raw.zst)
    └── annotation: disktype=applehv
```

---

## テスト

### VM の作成

```bash
# Quay.io から (公開版)
podman machine init test \
  --image docker://quay.io/tnk4on/machine-os:5.8 --now

# ローカルレジストリから (開発用)
podman machine init test \
  --image docker://192.168.1.28:5000/podman/machine-os:5.8 \
  --tls-verify=false --now

# ファイルから (レジストリ不通時)
scp fedora43arm-root:/root/podman-machine-os/outdir/podman-machine.aarch64.applehv.raw.zst /tmp/
podman machine init test --image-path /tmp/podman-machine.aarch64.applehv.raw.zst --now
```

> [!NOTE]
> デフォルトマシンでない場合は `--now` 使用時に `-u=false` を付けてください。対話確認が出てブロックします。

### 基本検証

```bash
# x86_64 エミュレーション
podman run --rm --platform linux/amd64 alpine uname -m
# → x86_64

# ARM64 リグレッション確認
podman run --rm --platform linux/arm64 alpine uname -m
# → aarch64

# FEX binfmt handler 確認
podman machine ssh test cat /proc/sys/fs/binfmt_misc/FEX-x86_64
# → enabled, interpreter: /usr/bin/FEXInterpreter, flags: POCF
```

### テストスクリプト

```bash
# プレビューテスト (T1-T16)
./test.sh --connection test

# フルテスト (T1-T17)
./test.sh --connection test --full

# 環境変数テスト (E1-E15)
./test-env.sh --connection test
```

### クリーンアップ

```bash
podman machine rm -f test
```

---

## トラブルシューティング

### ビルドが途中で止まる

- **zstd の上書き確認**: Step 3 で `rm -f outdir/*.zst outdir/*.tar` を実行したか確認
- **ディスク容量不足**: `df -h /` で確認。`fstrim -v /` で回収、`rm -rf /var/cache/osbuild*` で解放

### FEXInterpreter が大きい (25MB)

`-DCMAKE_BUILD_TYPE=Release` が指定されていない可能性があります。Release ビルドは約 6MB です。Containerfile の cmake 行を確認してください。

### コンテナ内で `uname -m` が `aarch64` を返す

- binfmt handler が登録されていない: `cat /proc/sys/fs/binfmt_misc/FEX-x86_64`
- `--platform linux/amd64` を指定しているか確認
- OCI hook が有効か: `ls /etc/containers/oci/hooks.d/fex-emu-hook.json`

### OSBuild エラー

```bash
# キャッシュを完全削除して再試行
rm -rf /var/cache/osbuild* /var/tmp/osbuild*
setenforce 0
```

### ビルド変更をローカルに同期

ビルドサーバーで変更したファイルはローカルにも反映してください:

```bash
# 変更確認
ssh fedora43arm-root "cd /root/podman-machine-os && git status --short"

# rsync で同期
rsync -avz --exclude='.git' --exclude='outdir' --exclude='rpms' \
  --exclude='build.sh.bak' --exclude='cache' \
  fedora43arm-root:/root/podman-machine-os/podman-image/ \
  repos/podman-machine-os/podman-image/
```
