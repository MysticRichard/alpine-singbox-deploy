# 公共规则与客户端私有规则

新装内置 8,633 条公共规则，按原顺序写入订阅。规则由 FlClash/Mihomo 在客户端执行，不加载进 VPS 的 sing-box 核心；服务器仅托管 YAML 文件。

## 来源与隐私复核

来源为同一维护者的 Debian 项目 `personal-xray-deploy` 中已脱敏的 `rules.template.yaml`，本次迁移不读取含凭据的完整客户端配置。

- 模板 SHA256：`b284b1a909b8edcac96db1b07f384dd875e134e199b98ec3f7615200133d6bd1`。
- 保留所有条目及原顺序，最后仅有一条 `MATCH,PROXY`。
- 保留通用保留网段（例如 `192.168.0.0/16`、`100.64.0.0/10`），它们是通用路由策略，不包含个人设备的具体地址。
- `172.16.102.56/32` 是公共 TeamViewer 规则，已与 [ACL4SSR 的 TeamViewer.list](https://github.com/ACL4SSR/ACL4SSR/blob/master/Clash/Ruleset/TeamViewer.list) 核对；不是个人设备地址。
- 模板中 DDNS 域名 `tr4ck3r.duckdns.org` 已与 [公开 trackerslist](https://github.com/ngosang/trackerslist/blob/master/trackers_all.txt) 核对；不是个人自有域名。
- 具体 NAS/内网设备地址、个人 Tailscale 地址和自有域名继续保存在客户端本地，不加入公开模板。

复核日期：2026年11月2日。当前设备未找到原始完整私有配置，因此不能声称重新逐条比对了全部个人规则。已有本地覆写应继续保留；此修复只迁移已脱敏公共模板。

## VPS 公共规则

路径：`/etc/singbox-sub/rules.yaml`。

- 新装：从单文件脚本内置模板创建。
- 重装：保留已有文件，空文件或格式错误直接报错，不用默认模板覆盖。
- 修改后：`sb-admin --update-sub`（或菜单 5），然后在 FlClash 刷新订阅。
- 生成前校验格式、策略名和唯一的末尾 MATCH；通过后原子替换，失败保留原订阅。
- 规则文件不在 HTTP 根目录中，HTTP 仅提供已生成的订阅。
- 不自动发现或合并 `private-rules.yaml` 等其他文件。

需要编辑时先做备份；只在此文件维护准备公开下发的规则。

## 客户端私有规则

将你原有的 NAS/Tailscale/自有域名规则继续放在 FlClash 的本地覆写/脚本中，并放在订阅公共规则前面，以便先匹配。

如果旧规则直接编辑在旧订阅里，它们不会自动出现在新订阅中。迁移前把这些条目另存到私人备份，再配置为新订阅适用的本地覆写。不要把包含实际私有条目的文件发到公开 issue 或提交进仓库。

占位示例（不是实际设备）：

```yaml
rules:
  - DOMAIN,my-device.example.invalid,DIRECT
  - IP-CIDR,192.0.2.10/32,DIRECT,no-resolve
```

该示例只能作为前置规则使用，不要用它替换整个订阅的 `rules`，否则会再次丢失公共分流。

## 构建和验证

```sh
python3 build.py
python3 build.py --check
python3 tests/check-public-rules.py
sh tests/test-rules.sh
```

源文件是 `src/alpine-singbox.sh.in` 与 `rules.template.yaml`；构建产物 `alpine-singbox.sh` 同时内置公共模板和订阅更新工具，所以 `curl | sh` 不依赖 GitHub 再下载规则。未来更新模板需复核隐私并更新快照哈希；不从原始客户端配置自动筛选和上传。
