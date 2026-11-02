# 设计与取舍

日期：2026-11-02。目标环境：Alpine 3.23 / OpenRC / x86_64 / 1 vCPU / 128 MB / NAT VPS。

## 目标

- 强协议、尽量防封
- 无面板
- 一条命令、填写端口
- 直接得到 FlClash 订阅地址
- 128 MB 内稳定运行

## 协议选择

采用 **VLESS + REALITY + XTLS Vision**，服务端用 Alpine 官方 `sing-box` 包。

理由：

1. REALITY 让节点看起来像真实 TLS 站点，不需要自有域名和证书。
2. Vision 处理 TLS-in-TLS 的流量特征，是 REALITY 组合里抗深度检测的重要一层。
3. sing-box 1.12 的 VLESS inbound 支持 `xtls-rprx-vision`（官方文档明确列出），因此不必为了 Vision 去手动维护 Xray 二进制。
4. 官方包由 Alpine 维护，`apk upgrade` 可跟进安全更新；OpenRC 服务文件也由 `sing-box-openrc` 提供。

未采用：

- Hysteria2：UDP 在部分 NAT/运营商环境不可用，且特征更明显；适合作为并行备选，不作为唯一入口。
- AnyTLS：客户端支持面不如 REALITY+Vision。
- Xray 手动二进制：供应链要自己维护；在 sing-box 支持 Vision 后不再必要。

## 架构

```text
客户端 FlClash
  |  VLESS + REALITY + Vision (TCP)
  v
公网 NAT 端口 -> 实例内部端口 (sing-box)
  |
  +-- REALITY handshake -> 目标站 TLS1.3/h2 伪装
  |
  +-- 订阅: busybox-extras httpd -> /srv/singbox-sub/<token>.yaml
```

组件：

| 组件 | 作用 |
|---|---|
| `sing-box` | 代理核心 |
| `sbox` | 自写 OpenRC 服务（`start-stop-daemon`，避免 supervise-daemon 在容器里的停止问题） |
| `sb-sub` | 订阅 HTTP 服务，运行用户 `sbsub` |
| `sb-admin` | 极简管理菜单 |
| `/etc/sing-box/state` | 端口、UUID、密钥，600 |

## 内存

- `GOMEMLIMIT=40MiB`、`GOGC=30`
- 不加载 `geoip.dat`；不使用 nginx、数据库、面板
- 订阅服务是单独的 busybox httpd，空闲占用很小

## 安全边界

- sing-box 以 root 运行（官方包默认行为）；单用户 NAT VPS 可接受
- 订阅服务降权到 `sbsub`
- token 600，订阅 YAML 644（token 在文件名里，属于访问控制）
- 订阅使用 HTTP；不要公开传播 URL
- 不修改云平台安全组/NAT 映射，只打印所需规则

## 验证记录

环境：`alpine:3.23` 容器（OpenRC，x86_64），2026-11-02。

已通过：

- `sh -n` 语法检查
- 目标 `www.apple.com:443` TLS1.3 + h2 + 证书预检
- `apk` 安装 `sing-box 1.12.12-r6`、`sing-box-openrc`、`busybox-extras`
- `sing-box check` 通过（REALITY + Vision 配置）
- `sbox` / `sb-sub` 启动，18443/18996 监听
- 订阅 `http://127.0.0.1:18996/<token>.yaml` 返回 YAML，含 `flow: xtls-rprx-vision`、`reality-opts`
- `--verify`：sing-box 客户端经 REALITY + Vision 出网成功
- 重装：UUID、密钥、配置 SHA256 不变，服务与订阅仍可用
- 卸载：配置/服务/订阅目录清理，保留 `/etc/singbox-sub` 与备份

未验证：

- 真实 NAT VPS 上的公网端口映射
- FlClash/mihomo 实际导入该订阅
- 不同目标站（Cloudflare/Samsung 等）的长期稳定性
- 128 MB 实机长时间运行的内存曲线

## 已知问题

- 容器内 OpenRC 的 `supervise-daemon` 在 stop 时可能卡住；因此服务改用 `start-stop-daemon`。
- Alpine 3.21/3.22 的 community 仓库没有 `sing-box`，脚本会提示使用 3.23+。
- `busybox` 本体不含 httpd，需要 `busybox-extras`；脚本会自动安装。
