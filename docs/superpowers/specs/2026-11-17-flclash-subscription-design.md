# FlClash 订阅与套餐信息设计

## 意图

让 Alpine 版提供与 Xray 部署相同的 FlClash 订阅额度信息，并允许订阅 HTTP 服务监听 NAT 分配的低位内部端口。

## 范围

- 安装时录入套餐总流量、每月重置日、到期日。
- 订阅响应发送 `Subscription-Userinfo`，包含手动上传/下载快照、总量和到期 Unix 时间。
- 管理命令可查看套餐和更新手动用量快照。
- 订阅 URL 使用 BusyBox httpd CGI，保留 token 访问控制。
- 订阅 OpenRC 服务仅在低端口绑定时获 `CAP_NET_BIND_SERVICE`，仍以 `sbsub` 用户运行。

## 不做

- 不自动采集代理流量，不执行限流或自动月度归零。
- 不声称 FlClash 能显示重置日；该日期只由管理命令展示。
- 不修改 NAT/防火墙映射；公网不可达仍需在供应商映射中排查。
- 不增加常驻 HTTP 依赖。

## 方案

复用 BusyBox httpd 的 CGI 能力，为 token URL 生成动态响应头并输出既有 YAML。额度格式沿用 Xray 项目的 `Subscription-Userinfo` 手动快照约定。OpenRC 订阅服务仍降权到 `sbsub`，仅订阅监听端口低于 1024 时配置绑定 capability。

## 验收

- 交互安装可输入 `100GB`、重置日 `1`–`31`（`0` 表示无固定日）、日期 `YYYY-MM-DD`（`0` 表示长期）。
- `sb-admin --plan` 显示保存的套餐值；`sb-admin --quota` 更新手动上传/下载快照。
- FlClash 订阅响应带正确额度头，订阅正文及错误 token 行为正确。
- 内部订阅端口 `1`–`65535` 均可通过格式校验；受限 Alpine 容器中低端口服务可启动并响应。
- 1 CPU / 128 MiB Alpine 3.23 完整安装回归通过。

## 已知外部限制

用户报告的公网订阅连接失败无法由脱敏地址复现。脚本本地 HTTP 自检不能证明平台端口转发或 FlClash 网络可达。
