[nexttrace](https://github.com/nxtrace/NTrace-core) 的 `.deb` 包，适用于 Debian 或基于 Debian 的发行版。

The `.deb` packages of [nexttrace](https://github.com/nxtrace/NTrace-core), suitable for Debian and Debian-based distros.


## Usage/用法

### 直接下载 .deb 文件

直接从 [Releases](https://github.com/nxtrace/nexttrace-debs/releases) 下载 .deb 文件。

### 添加 apt 仓库

```sh
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://github.com/nxtrace/nexttrace-debs/releases/latest/download/nexttrace-archive-keyring.gpg | sudo tee /etc/apt/keyrings/nexttrace.gpg >/dev/null
echo "Types: deb
URIs: https://github.com/nxtrace/nexttrace-debs/releases/latest/download/
Suites: ./
Signed-By: /etc/apt/keyrings/nexttrace.gpg" | sudo tee /etc/apt/sources.list.d/nexttrace.sources >/dev/null
sudo apt update
sudo apt install nexttrace
```

> 如果你更喜欢 ASCII armor 格式，也可以下载 `nexttrace-archive-keyring.asc`。

### add apt repository

```sh
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://github.com/nxtrace/nexttrace-debs/releases/latest/download/nexttrace-archive-keyring.gpg | sudo tee /etc/apt/keyrings/nexttrace.gpg >/dev/null
echo "Types: deb
URIs: https://github.com/nxtrace/nexttrace-debs/releases/latest/download/
Suites: ./
Signed-By: /etc/apt/keyrings/nexttrace.gpg" | sudo tee /etc/apt/sources.list.d/nexttrace.sources >/dev/null
sudo apt update
sudo apt install nexttrace
```

> `nexttrace-archive-keyring.asc` is also published if you prefer an ASCII-armored key.

## Maintainer notes / 维护者说明

- 运行 `build.sh` 时可以通过以下环境变量开启 Release 签名：
  - `SIGNING_KEY_ID`：用于签名的 GPG key ID 或指纹。
  - `SIGNING_KEY`：可选，ASCII 私钥内容，会在临时 `GNUPGHOME` 中导入。
  - `SIGNING_KEY_FILE`：可选，指向包含私钥的文件路径。
  - `SIGNING_KEY_PASSPHRASE`：可选，若私钥有口令请设置。
- 当签名启用时，脚本会生成 `Release.gpg`、`InRelease` 以及 `nexttrace-archive-keyring.gpg/.asc`，上传到 Release 里供用户使用。
