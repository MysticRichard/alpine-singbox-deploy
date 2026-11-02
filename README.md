# Alpine sing-box 一键部署

面向 **Alpine 3.23 / OpenRC / x86_64 / 1C 128MB NAT VPS** 的单文件脚本：

- 使用 Alpine 官方 `sing-box` 包（签名包，`apk` 可维护）
- VLESS + REALITY + **XTLS Vision**
- 无面板、无数据库、无 geoip 文件
- 填几个端口，直接输出 FlClash 订阅地址

## 为什么用官方 sing-box

Alpine 3.23 的 community 仓库提供：

```text
sing-box          1.12.12-r6
sing-box-openrc   1.12.12-r6
```

sing-box 官方支持 VLESS 的 `xtls-rprx-vision` flow（见 [官方文档](https://sing-box.sagernet.org/configuration/inbound/vless/)），因此可以同时拿到：

- 发行版签名包和 OpenRC 服务；
- REALITY + Vision 的抗封组合；
- 128 MB 能承受的内存占用。

不需要手动下载 Xray 二进制，也不依赖 systemd。

## 要求

- Alpine **3.23+**（3.21/3.22 的 community 仓库没有 `sing-box` 包）
- x86_64
- OpenRC（`rc-service` 可用）
- root
- 根分区至少 50 MB 可用

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/MysticRichard/alpine-singbox-deploy/main/alpine-singbox.sh -o /tmp/alpine-singbox.sh
sh /tmp/alpine-singbox.sh
```

也支持管道运行（提示会从 `/dev/tty` 读取）：

```sh
curl -fsSL https://raw.githubusercontent.com/MysticRichard/alpine-singbox-deploy/main/alpine-singbox.sh | sh
```

依次询问：

| # | 项目 | 说明 |
|---|---|---|
| 1 | 公网 IP 或域名 | 客户端连接地址 |
| 2 | 代理公网 TCP 端口 | NAT 外部端口；能 443 就 443 |
| 3 | 代理内部 TCP 端口 | 实例监听端口，通常是平台映射的内部端口 |
| 4 | REALITY 目标 | 默认 `www.apple.com:443`，会现场校验 TLS1.3 + h2 + 证书 |
| 5 | serverName | 默认跟随目标 |
| 6 | 订阅公网 TCP 端口 | NAT 外部端口 |
| 7 | 订阅内部 TCP 端口 | 必须 >=1024 |

无人值守：

```sh
NONINTERACTIVE=1 \
SERVER_ADDRESS=203.0.113.10 \
PUBLIC_PORT=443 LISTEN_PORT=2082 \
SUB_PUBLIC_PORT=34441 SUB_LISTEN_PORT=2096 \
sh alpine-singbox.sh --yes
```

装完输出：

```text
http://<公网地址>:<订阅公网端口>/<token>.yaml
```

导入 FlClash 即可。订阅只带最小规则（`GEOIP,CN,DIRECT` + `MATCH,PROXY`），私有设备规则放 FlClash 本地覆写。

## 管理

```sh
sb-admin            # 状态 / 订阅地址 / 重启 / 卸载
sb-admin --sub      # 只打印订阅地址
sb-admin --status
```

## 自检

```sh
sh alpine-singbox.sh --verify
```

会临时启动一个 sing-box 客户端，经 REALITY + Vision 访问 Cloudflare trace 或目标站，确认 UUID、flow、target 和端口真的能出网。

## 卸载

```sh
sh alpine-singbox.sh --uninstall          # 保留 /etc/singbox-sub 与备份
sh alpine-singbox.sh --uninstall --purge  # 连 token/订阅状态一起删
```

`sing-box` 软件包会保留；需要时手动 `apk del sing-box sing-box-openrc`。

## 128 MB 说明

- `GOMEMLIMIT=40MiB`、`GOGC=30`
- 不加载 geoip.dat；只监听代理和订阅两个端口
- 订阅由 `busybox-extras` 的 httpd 提供，无 CGI、无数据库
- 不提供配额显示；NAT 套餐以供应商后台为准

## 限制

- 仅 Alpine + OpenRC；Debian/systemd 请用 [personal-xray-deploy](https://github.com/MysticRichard/personal-xray-deploy)
- 仅 amd64
- 不支持 IPv6 字面量作为公网地址
- 订阅是 HTTP；token 只控制访问，不加密传输
- 不保证 IP 不被封；IP、端口、目标、客户端版本同样重要
- 目前用 sing-box 客户端自检，FlClash/mihomo 实际导入仍需人工复测

## 测试

已在一个 `alpine:3.23` 容器内完成：

- 目标 TLS1.3/h2 预检
- `apk` 安装 `sing-box` / `sing-box-openrc` / `busybox-extras`
- REALITY + Vision 配置校验
- OpenRC 启动、端口监听
- 订阅 HTTP 自检与 YAML 内容校验
- `--verify` 端到端
- 重装幂等（UUID/密钥/配置哈希不变）
- 卸载清理

测试脚本见 [`tests/`](tests/)。

## 文件

| 文件 | 用途 |
|---|---|
| `alpine-singbox.sh` | 单文件安装器 + 管理入口 |
| `tests/` | Alpine 容器回归 |
| `docs/design.md` | 方案取舍、架构与验证记录 |
