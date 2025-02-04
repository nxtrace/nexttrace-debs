[nexttrace](https://github.com/nxtrace/NTrace-core) 的 `.deb` 包，适用于 Debian 或基于 Debian 的发行版。

The `.deb` packages of [nexttrace](https://github.com/nxtrace/NTrace-core), suitable for Debian and Debian-based distros.


## Usage/用法

### 直接下载 .deb 文件

直接从 [Releases](https://github.com/nxtrace/nexttrace-debs/releases) 下载 .deb 文件。

### 添加 apt 仓库

```sh
echo "Types: deb
URIs: https://github.com/nxtrace/nexttrace-debs/releases/latest/download/
Suites: ./
Trusted: yes" | sudo tee /etc/apt/sources.list.d/nexttrace.sources
sudo apt update
sudo apt install nexttrace
```
