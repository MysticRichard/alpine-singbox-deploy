# Alpine / OpenRC 版（Xray 原型，已归档）

> **已归档，不再维护。** 2026-11-02 起改用 `alpine-singbox.sh`：Alpine 官方 sing-box 包同样支持 REALITY + Vision，供应链更稳。本文仅保留当时的 Xray 方案记录。

面向 1 vCPU / 128 MB 的 NAT VPS：单文件、无面板、Xray v26.6.27 + VLESS + XTLS Vision + REALITY，装完直接给 FlClash 订阅地址。

## 为什么不是官方 sing-box 包

Alpine 3.23 的 `sing-box` 包供应链更稳，但 sing-box 不支持 Xray 的 `xtls-rprx-vision` flow。REALITY 负责“像真站”，Vision 负责“TLS 里再套 TLS 的流量特征”；少了 Vision，抗深度检测弱一档。

因此这里选择：

- 固定 Xray **v26.6.27**（与 FlClash/mihomo 实测兼容；v26.7.11+ 的 `minClientVer` 会让 mihomo 认证失败）
- 官方 GitHub Release 二进制
- 固定 SHA256 `b3e5902d…` 校验
- 静态 Go 二进制，不依赖 glibc/gcompat

如果只想三条命令、能接受没有 Vision，用官方包：

```bash
apk add --no-cache sing-box sing-box-openrc
# /etc/sing-box/config.json，VLESS + REALITY，客户端不要写 flow
rc-update add sing-box default
rc-service sing-box start
```

## 要求

- Alpine **3.21+**，推荐 **3.23**（支持到 2027-11）
- x86_64
- OpenRC（`rc-service` 可用）
- root
- 根分区至少 80 MB 可用

## 安装

```bash
sh alpine-xray.sh
```

依次询问：

1. VPS 公网 IP 或域名
2. 代理公网 TCP 端口（NAT 外部端口；能 443 就 443）
3. 代理内部 TCP 端口（实例监听端口）
4. REALITY 目标（默认 `www.apple.com:443`，会现场校验 TLS1.3 + h2 + 证书）
5. serverName（默认跟随目标）
6. 订阅公网 TCP 端口
7. 订阅内部 TCP 端口（>=1024）

无人值守：

```bash
NONINTERACTIVE=1 \
SERVER_ADDRESS=203.0.113.10 \
PUBLIC_PORT=443 LISTEN_PORT=2082 \
SUB_PUBLIC_PORT=34441 SUB_LISTEN_PORT=2096 \
sh alpine-xray.sh --yes
```

装完输出：

```text
http://<公网地址>:<订阅公网端口>/<token>.yaml
```

直接导入 FlClash。订阅是最小规则（`GEOIP,CN,DIRECT` + `MATCH,PROXY`），私有规则放 FlClash 本地覆写。

## 管理

```bash
xray-admin            # 状态 / 订阅地址 / 重启 / 卸载
xray-admin --sub      # 只打印订阅地址
xray-admin --status
```

## 自检

```bash
sh alpine-xray.sh --verify
```

会临时起一个本地 Xray 客户端，经 REALITY 访问 Cloudflare trace 或目标站，确认 UUID、flow、target、端口真的能出网。

## 卸载

```bash
sh alpine-xray.sh --uninstall          # 保留 /etc/xray-sub 与备份
sh alpine-xray.sh --uninstall --purge  # 连 token/订阅状态一起删
```

## 128 MB 说明

- `GOMEMLIMIT=40MiB`、`GOGC=30`
- 不加载 geoip.dat；只拦私网和常见滥用端口
- 订阅由 busybox httpd 提供，无 CGI、无数据库
- 不提供配额显示；NAT 套餐以供应商后台为准

## 限制

- 仅 amd64；不支持 arm64
- 仅 OpenRC；Debian/systemd 用仓库根目录的 Debian 版
- 不支持 IPv6 字面量作为公网地址
- 订阅是 HTTP；token 只控制访问，不加密传输
- 不保证 IP 不被封；协议只是一层，IP/端口/目标同样重要

## 测试状态

在 `alpine:3.23` 容器内做真实安装回归：目标 TLS 预检、下载与 SHA256、配置校验、OpenRC 启动、订阅自检、`--verify`、卸载。结果以实际测试输出为准，未完成前不标记“已验收”。
