[nexttrace](https://github.com/nxtrace/NTrace-core) 的 `.deb` 包，适用于 Debian 或基于 Debian 的发行版。

The `.deb` packages of [nexttrace](https://github.com/nxtrace/NTrace-core), suitable for Debian and Debian-based distros.

## Packages / 包

- `nexttrace`：完整版，包含 traceroute、MTR、Globalping、WebUI。
- `nexttrace-tiny`：精简版，支持 traceroute、MTR、MTU 和 Fast Trace。
- `ntr`：MTR 专用版。

## Architectures / 架构

当前 apt 仓库发布以下 Debian 架构：

- `amd64`
- `i386`
- `arm64`
- `armel`
- `armhf`
- `loong64`
- `mipsel`
- `mips64el`
- `ppc64el`
- `riscv64`
- `s390x`

## Usage/用法

### Download `.deb` files directly / 直接下载 `.deb` 文件

直接从 [Releases](https://github.com/nxtrace/nexttrace-debs/releases) 下载 .deb 文件。

### Add apt repository / 添加 apt 仓库

```sh
sudo apt install curl gpg
```

```sh
(
    set -e
    key_tmp=$(mktemp -d)
    trap 'rm -rf "$key_tmp"' EXIT
    curl -fsSL -o "$key_tmp/nexttrace.gpg" https://github.com/nxtrace/nexttrace-debs/releases/latest/download/nexttrace-archive-keyring.gpg
    key_info=$(gpg --batch --no-options --homedir "$key_tmp" --show-keys --with-colons "$key_tmp/nexttrace.gpg")
    fingerprint=$(printf '%s\n' "$key_info" | awk -F: '$1 == "pub" { primary = 1 } $1 == "fpr" && primary { print $10; primary = 0 }')
    if [ "$fingerprint" != A2A1FB99E3A11D5B146E170B36281AB257B307FA ]; then
        echo 'NextTrace archive key fingerprint mismatch' >&2
        exit 1
    fi

    sudo install -d -m 0755 /etc/apt/keyrings
    sudo install -m 0644 "$key_tmp/nexttrace.gpg" /etc/apt/keyrings/nexttrace.gpg
    sudo tee /etc/apt/sources.list.d/nexttrace.sources >/dev/null <<'EOF'
Types: deb
URIs: https://github.com/nxtrace/nexttrace-debs/releases/latest/download/
Suites: ./
Signed-By: /etc/apt/keyrings/nexttrace.gpg
EOF
    sudo apt update
    sudo apt install nexttrace
)
```

> 如果你更喜欢 ASCII armor 格式，也可以下载 `nexttrace-archive-keyring.asc`。

> `nexttrace-archive-keyring.asc` is also published if you prefer an ASCII-armored key.

### Install a specific flavor / 安装指定 flavor

```sh
sudo apt install nexttrace
sudo apt install nexttrace-tiny
sudo apt install ntr
```

三个包可以共存安装，二进制分别为 `/usr/bin/nexttrace`、`/usr/bin/nexttrace-tiny`、`/usr/bin/ntr`。

## Maintainer notes / 维护者说明

- 在 Debian 或 Ubuntu 安装 `curl`、`dpkg`、`apt-utils`、`python3` 和 `xz-utils` 后，可运行 `./build.sh <tag> [revision]`，产物位于 `output/`。
- 修订号默认为 `1`。本地运行 `./build.sh v1.7.6 2` 会生成版本 `1.7.6+2`。在 GitHub Actions 手动运行时可填写 `tag: v1.7.6` 和 `revision: 2`，对应 Release 标签 `debian-v1.7.6-r2`。
- 预发布不进入 APT 源。CI 仅发布比当前 APT 版本更新的正式版本。
- 本地构建可通过以下环境变量开启 Release 签名：
  - `SIGNING_KEY_ID`：用于签名的 GPG key ID 或指纹。
  - `SIGNING_KEY`：可选，ASCII 私钥内容，会在临时 `GNUPGHOME` 中导入。
  - `SIGNING_KEY_FILE`：可选，指向包含私钥的文件路径。
  - `SIGNING_KEY_PASSPHRASE`：可选，若私钥有口令请设置。
- `build.sh` 会为 3 个 flavor 与 11 个 Debian 架构组合构建 `.deb`，共 33 个包。
- Debian 架构映射到上游 Linux 产物如下：
  - `amd64 -> amd64`
  - `i386 -> 386`
  - `arm64 -> arm64`
  - `armel -> armv5`
  - `armhf -> armv7`
  - `loong64 -> loong64`
  - `mipsel -> mipsle`
  - `mips64el -> mips64le`
  - `ppc64el -> ppc64le`
  - `riscv64 -> riscv64`
  - `s390x -> s390x`
- 当签名启用时，脚本会生成 `Release.gpg`、`InRelease` 以及 `nexttrace-archive-keyring.gpg/.asc`，上传到 Release 里供用户使用。
