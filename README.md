# PProxy

花 0 秒时间，在任意服务器上启动代理客户端和 WebUI。

## 特性

- 单文件：不需要克隆整个仓库，只需下载一个文件 `proxy.sh`，并运行它
- 最小依赖：仅依赖 Bash、Curl 和[最基本的 GNU 工具集](https://github.com/w568w/pproxy/blob/main/proxy.sh#L3)，几乎在任何发行版上都可以运行
- 网络友好：内置 GitHub 镜像源和智能测速选择，无需另外下载
- 整洁：所有文件放置在同一目录的 `./proxy-data` 下，运行期间绝不创建任何额外目录、垃圾文件或临时文件
- 先进：使用最新的 [Mihomo](https://github.com/MetaCubeX/mihomo) 内核 + [metacubexd](https://github.com/metacubex/metacubexd) 网页前端，支持几乎所有协议
- 兼容性和可移植性：编写过程中尽可能考虑到了所有可能的情况并遵循最佳实践，不对系统/平台做任何假设，不存在任何行为硬编码

## 如何使用

```bash
wget https://raw.githubusercontent.com/w568w/pproxy/main/proxy.sh
```

如果无法访问 GitHub，可以使用镜像源下载，例如：

```bash
wget https://github.akams.cn/https://raw.githubusercontent.com/w568w/pproxy/main/proxy.sh
```

下载后执行 `bash proxy.sh` 即可启动代理。

```bash
$ bash proxy.sh
[INFO] Mihomo already exists, skip downloading. Version: 
Mihomo Meta v1.19.7 linux amd64 with go1.24.3 Mon May 12 02:04:51 UTC 2025
Use tags: with_gvisor
[INFO] metacubexd already exists, skip downloading.
[INFO] Mihomo started in the background. You can access the web UI at http://<server-ip>:9091/ui
[INFO] You may need to put your subscription file at proxy-data/config/config.yaml and restart Mihomo.
[INFO] To stop Mihomo, run: proxy.sh stop
```

## TODO

- [ ] 自动下载订阅配置文件
- [x] 自动配置 WebUI 端口映射，方便在 SSH 服务器上使用
