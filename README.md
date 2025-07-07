# PProxy

花 0 秒时间，在任意服务器上启动代理客户端和 WebUI。

## 特性

- **单文件**：不需要克隆整个仓库，只需下载一个文件 `proxy.sh`，并运行它
- **最小依赖**：仅依赖 Bash、Curl 和[最基本的 GNU 工具集](https://github.com/w568w/pproxy/blob/main/proxy.sh#L12)，几乎在任何发行版上都可以运行
- **网络友好**：内置 GitHub 镜像源和智能测速选择，无需另外下载
- **整洁**：所有文件放置在同一目录的 `./proxy-data` 下，运行期间绝不创建任何额外目录、垃圾文件或临时文件
- **先进**：使用最新的 [Mihomo](https://github.com/MetaCubeX/mihomo) 内核 + [metacubexd](https://github.com/metacubex/metacubexd) 网页前端，支持几乎所有协议
- **兼容性和可移植性**：编写过程中尽可能考虑到了所有可能的情况并遵循最佳实践，不对系统/平台做任何假设，不存在任何行为硬编码
- **幂等**：多次运行不会产生副作用。运行两次 `proxy.sh` 不会下载两次 Mihomo 或 metacubexd，也不会启动两个代理服务

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

### 常用命令

```bash
# （如果需要下载，则）下载代理，然后（重新）启动代理，交互式输入配置并启动 WebUI 和隧道服务
# 如果之前已有配置文件则不会要求输入
$ bash proxy.sh
# 同上，下载订阅 URL 为配置文件
$ bash proxy.sh https://example.com/subscription.yaml
# 下载并启动代理，从标准输入读取配置文件（在 SSH 服务器上粘贴配置时很有用）
$ bash proxy.sh -
# 检查当前代理运行状态
$ bash proxy.sh status
# 停止代理
$ bash proxy.sh stop
# 对已运行在 9000 端口的 WebUI 进行端口映射，以便访问和管理
$ bash proxy.sh tunnel 9000
# 查看帮助信息
$ bash proxy.sh help 或 $ bash proxy.sh -h 或 $ bash proxy.sh --help
```

### 注意事项

- `proxy.sh` 仅支持 Clash / Clash Meta / Mihomo 的配置文件格式，从你的代理服务商获取配置文件时请注意。

## TODO

- [x] 下载订阅配置文件
- [x] 自动配置 WebUI 端口映射，方便在 SSH 服务器上使用
- [x] 支持 help、status、restart、tunnel 子命令
