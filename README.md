自行打包的 [nexttrace](https://github.com/nxtrace/NTrace-core)，供 Debian 或其他发行版上使用。

Self-packaged [nexttrace](https://github.com/nxtrace/NTrace-core) for use on Debian or other distro.


## Usage/用法

```sh
echo "deb [trusted=yes] https://github.com/nxtrace/nexttrace-debs/releases/latest/download ./" |
    sudo tee /etc/apt/sources.list.d/nexttrace.list
sudo apt update
```
