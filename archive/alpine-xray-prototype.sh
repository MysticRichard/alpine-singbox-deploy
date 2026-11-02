#!/bin/sh
# UNMAINTAINED PROTOTYPE (2026-11-02): manual Xray v26.6.27 + OpenRC.
# Superseded by ../alpine-singbox.sh (official Alpine sing-box + Vision).
# Kept for reference only; not part of the tested delivery.
# Alpine 3.21+ / OpenRC / x86_64 NAT VPS
# VLESS + XTLS Vision + REALITY + Clash/Mihomo subscription.
# No panel, no database, no geoip file. Designed for 1 vCPU / 128 MB.
set -eu
umask 077

VERSION=v26.6.27
ARCHIVE_SHA256=b3e5902d06d6282fe53cfa2fc426058b9aeaa429b2c812e20887cd47f26d08bf
XRAY_BIN=/usr/local/bin/xray
XRAY_RUN=/usr/local/bin/xray-run
XRAY_ETC=/usr/local/etc/xray
XRAY_ASSETS=/usr/local/share/xray
XRAY_LOG=/var/log/xray
STATE=$XRAY_ETC/state
SUB_ETC=/etc/xray-sub
SUB_ROOT=/srv/sub
SUB_TOKEN_FILE=$SUB_ETC/token
SUB_PORT_FILE=$SUB_ETC/port
ADMIN=/usr/local/sbin/xray-admin
BACKUP_ROOT=/root/xray-backups

fail() { printf 'ERROR: %s\n' "$*" >&2; FAILED=1; exit 1; }
info() { printf '%s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
用法：
  sh alpine-xray.sh                 交互安装（推荐）
  sh alpine-xray.sh --yes ...       无人值守安装
  sh alpine-xray.sh --verify        自检已安装节点
  sh alpine-xray.sh --uninstall     卸载（保留 /root/xray-backups）
  sh alpine-xray.sh --help

参数：
  --server IP_OR_HOST       公网地址
  --port PORT               代理公网 TCP 端口
  --listen-port PORT        代理内部 TCP 端口
  --sub-port PORT           订阅公网 TCP 端口
  --sub-listen-port PORT    订阅内部 TCP 端口（>=1024）
  --target HOST:PORT        REALITY 目标，默认 www.apple.com:443
  --sni NAME                serverName，默认跟随目标
  --yes                     无人值守；所有必填项必须给出
  --uninstall [--purge]     卸载；--purge 同时删除 /etc/xray-sub
  --verify                  临时客户端实测链路
USAGE
}

ACTION=install
PURGE=0
SERVER_ADDRESS=${SERVER_ADDRESS:-}
PUBLIC_PORT=${PUBLIC_PORT:-}
LISTEN_PORT=${LISTEN_PORT:-}
SUB_PUBLIC_PORT=${SUB_PUBLIC_PORT:-}
SUB_LISTEN_PORT=${SUB_LISTEN_PORT:-}
REALITY_DEST=${REALITY_DEST:-}
REALITY_SERVER_NAME=${REALITY_SERVER_NAME:-}
NONINTERACTIVE=${NONINTERACTIVE:-0}

while [ $# -gt 0 ]; do
  case $1 in
    --server) SERVER_ADDRESS=${2:-}; shift 2 || fail '--server 缺少值';;
    --port) PUBLIC_PORT=${2:-}; shift 2 || fail '--port 缺少值';;
    --listen-port) LISTEN_PORT=${2:-}; shift 2 || fail '--listen-port 缺少值';;
    --sub-port) SUB_PUBLIC_PORT=${2:-}; shift 2 || fail '--sub-port 缺少值';;
    --sub-listen-port) SUB_LISTEN_PORT=${2:-}; shift 2 || fail '--sub-listen-port 缺少值';;
    --target) REALITY_DEST=${2:-}; shift 2 || fail '--target 缺少值';;
    --sni) REALITY_SERVER_NAME=${2:-}; shift 2 || fail '--sni 缺少值';;
    --yes) NONINTERACTIVE=1; shift;;
    --uninstall) ACTION=uninstall; shift;;
    --purge) PURGE=1; shift;;
    --verify) ACTION=verify; shift;;
    -h|--help) usage; exit 0;;
    *) fail "未知参数：$1（用 --help 查看用法）";;
  esac
done

valid_port() {
  case ${1:-} in ''|*[!0-9]*) return 1;; esac
  [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

valid_host() {
  case ${1:-} in ''|*[!A-Za-z0-9.-]*) return 1;; esac
  return 0
}

need_root() { [ "$(id -u)" -eq 0 ] || fail '请用 root 运行'; }

need_alpine() {
  [ -f /etc/alpine-release ] || fail '仅支持 Alpine Linux'
  command -v rc-service >/dev/null 2>&1 || fail '需要 OpenRC（rc-service）'
  [ "$(uname -m)" = x86_64 ] || fail '当前仅支持 x86_64'
}

# Prompts read from the terminal even when the script arrives through a pipe.
TTY_FD=0
if [ "$NONINTERACTIVE" != 1 ] && [ ! -t 0 ]; then
  if exec 3</dev/tty 2>/dev/null; then TTY_FD=3; else
    fail '需要交互终端：请用 ssh -t 或 bash <(curl ...) 运行'
  fi
fi

ask() {
  _label=$1; _def=${2:-}; _ans=
  while :; do
    if [ -n "$_def" ]; then printf '%s [%s]: ' "$_label" "$_def" >&2; else printf '%s: ' "$_label" >&2; fi
    if [ "$TTY_FD" = 3 ]; then IFS= read -r _ans <&3 || fail '读取输入失败'; else IFS= read -r _ans || fail '读取输入失败'; fi
    _ans=${_ans:-$_def}
    [ -n "$_ans" ] && break
    printf '不能为空\n' >&2
  done
  printf '%s' "$_ans"
}

load_state() {
  if [ -f "$STATE" ]; then
    # shellcheck disable=SC1090
    . "$STATE"
  fi
}

save_state() {
  {
    printf 'SERVER_ADDRESS=%s\n' "$SERVER_ADDRESS"
    printf 'PUBLIC_PORT=%s\n' "$PUBLIC_PORT"
    printf 'LISTEN_PORT=%s\n' "$LISTEN_PORT"
    printf 'SUB_PUBLIC_PORT=%s\n' "$SUB_PUBLIC_PORT"
    printf 'SUB_LISTEN_PORT=%s\n' "$SUB_LISTEN_PORT"
    printf 'REALITY_DEST=%s\n' "$REALITY_DEST"
    printf 'REALITY_SERVER_NAME=%s\n' "$REALITY_SERVER_NAME"
    printf 'CLIENT_UUID=%s\n' "$CLIENT_UUID"
    printf 'PRIVATE_KEY=%s\n' "$PRIVATE_KEY"
    printf 'PUBLIC_KEY=%s\n' "$PUBLIC_KEY"
    printf 'SHORT_ID=%s\n' "$SHORT_ID"
  } > "$STATE"
  chmod 600 "$STATE"
  chown root:root "$STATE"
}

validate() {
  valid_host "$SERVER_ADDRESS" || fail '公网地址只能是 IPv4 或域名'
  valid_port "$PUBLIC_PORT" || fail '代理公网端口无效'
  valid_port "$LISTEN_PORT" || fail '代理内部端口无效'
  valid_port "$SUB_PUBLIC_PORT" || fail '订阅公网端口无效'
  valid_port "$SUB_LISTEN_PORT" || fail '订阅内部端口无效'
  [ "$SUB_LISTEN_PORT" -ge 1024 ] || fail '订阅内部端口必须 >=1024'
  [ "$PUBLIC_PORT" != "$SUB_PUBLIC_PORT" ] || fail '代理和订阅的公网端口不能相同'
  [ "$LISTEN_PORT" != "$SUB_LISTEN_PORT" ] || fail '代理和订阅的内部端口不能相同'
  case $REALITY_DEST in *:*) ;; *) fail 'REALITY 目标格式应为 host:port';; esac
  DEST_HOST=${REALITY_DEST%:*}
  DEST_PORT=${REALITY_DEST##*:}
  valid_host "$DEST_HOST" || fail 'REALITY 目标主机无效'
  valid_port "$DEST_PORT" || fail 'REALITY 目标端口无效'
  [ -n "$REALITY_SERVER_NAME" ] || REALITY_SERVER_NAME=$DEST_HOST
  [ "$REALITY_SERVER_NAME" = "$DEST_HOST" ] || fail 'serverName 必须与目标主机一致'
}

port_busy() {
  netstat -ltn 2>/dev/null | awk -v p=":$1" '$4 ~ p"$" {f=1} END{exit !f}'
}

check_target_tls() {
  probe=$(openssl s_client -4 -connect "$REALITY_DEST" -servername "$REALITY_SERVER_NAME" \
    -verify_hostname "$REALITY_SERVER_NAME" -verify_return_error -tls1_3 -alpn h2 </dev/null 2>&1) || {
      printf '%s\n' "$probe" | tail -15 >&2
      fail 'REALITY 目标 TLS 校验失败（检查 VPS 时间、CA 和目标站）'
    }
  case $probe in
    *TLSv1.3*) ;;
    *) fail 'REALITY 目标未协商 TLS1.3';;
  esac
  case $probe in
    *'ALPN protocol: h2'*) ;;
    *) fail 'REALITY 目标未协商 h2';;
  esac
}

preflight() {
  need_root
  need_alpine
  for c in curl openssl sha256sum awk sed grep netstat; do
    command -v "$c" >/dev/null 2>&1 || fail "缺少 $c；先执行 apk add ca-certificates curl openssl"
  done
  free_kb=$(df -Pk / | awk 'NR==2 {print $4}')
  [ "${free_kb:-0}" -ge 80000 ] || fail '根分区可用空间不足 80 MB'
  if port_busy "$LISTEN_PORT"; then
    old_port=
    [ -f "$STATE" ] && old_port=$(sed -n 's/^LISTEN_PORT=//p' "$STATE" 2>/dev/null)
    if [ "$old_port" != "$LISTEN_PORT" ] || ! rc-service xray status >/dev/null 2>&1; then
      fail "内部端口 $LISTEN_PORT 已被占用"
    fi
  fi
  if port_busy "$SUB_LISTEN_PORT"; then
    old_sub=
    [ -f "$STATE" ] && old_sub=$(sed -n 's/^SUB_LISTEN_PORT=//p' "$STATE" 2>/dev/null)
    if [ "$old_sub" != "$SUB_LISTEN_PORT" ] || ! rc-service xray-sub status >/dev/null 2>&1; then
      fail "订阅内部端口 $SUB_LISTEN_PORT 已被占用"
    fi
  fi
  info '检查 REALITY 目标 TLS1.3/h2 …'
  check_target_tls
  info "PASS: 目标 $REALITY_DEST（$REALITY_SERVER_NAME）"
}

ensure_deps() {
  command -v curl >/dev/null 2>&1 || apk add --no-cache ca-certificates curl >/dev/null
  command -v openssl >/dev/null 2>&1 || apk add --no-cache openssl >/dev/null
  if ! busybox --list 2>/dev/null | grep -qx unzip; then
    command -v unzip >/dev/null 2>&1 || apk add --no-cache unzip >/dev/null
  fi
}

download_release() {
  out=$1
  release="XTLS/Xray-core/releases/download/$VERSION/Xray-linux-64.zip"
  for base in \
    "https://github.com/$release" \
    "https://ghfast.top/https://github.com/$release" \
    "https://gh-proxy.com/https://github.com/$release" \
    "https://ghproxy.net/https://github.com/$release"; do
    info "下载 $base"
    if curl -fL --retry 3 --retry-delay 2 --continue-at - \
      --connect-timeout 15 --max-time 600 "$base" -o "$out"; then
      if printf '%s  %s\n' "$ARCHIVE_SHA256" "$out" | sha256sum -c - >/dev/null 2>&1; then
        return 0
      fi
      info 'SHA256 不匹配，换下一个源'
    fi
  done
  fail 'Xray 下载或校验失败；可稍后重试'
}

snapshot() {
  backup="$BACKUP_ROOT/$(date -u +%Y%m%dT%H%M%SZ)-$$"
  mkdir -p "$backup"
  for p in "$XRAY_ETC" "$XRAY_BIN" "$XRAY_RUN" /etc/init.d/xray /etc/init.d/xray-sub "$ADMIN" "$SUB_ETC" /srv/sub; do
    [ -e "$p" ] && cp -a "$p" "$backup/" 2>/dev/null || true
  done
  BACKUP=$backup
}

rollback() {
  [ -n "${BACKUP:-}" ] || return 0
  info "安装失败，正在从 $BACKUP 恢复"
  rc-service xray stop >/dev/null 2>&1 || true
  rc-service xray-sub stop >/dev/null 2>&1 || true
  for p in "$XRAY_ETC" "$XRAY_BIN" "$XRAY_RUN" /etc/init.d/xray /etc/init.d/xray-sub "$ADMIN" "$SUB_ETC" /srv/sub; do
    base=${p##*/}
    if [ -e "$BACKUP/$base" ]; then
      rm -rf "$p"
      cp -a "$BACKUP/$base" "$p" 2>/dev/null || true
    fi
  done
}

on_exit() {
  rc=$?
  trap - EXIT
  if [ -n "${TMPDIR_WORK:-}" ]; then rm -rf "$TMPDIR_WORK"; fi
  if [ "$rc" -ne 0 ] && [ "${FAILED:-0}" = 1 ]; then
    rollback
  fi
  exit "$rc"
}
trap on_exit EXIT

render_config() {
  cat > "$1" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "tag": "personal",
    "listen": "0.0.0.0",
    "port": $LISTEN_PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$CLIENT_UUID", "flow": "xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "target": "$REALITY_DEST",
        "xver": 0,
        "serverNames": ["$REALITY_SERVER_NAME"],
        "privateKey": "$PRIVATE_KEY",
        "shortIds": ["$SHORT_ID"]
      }
    }
  }],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [
      {"type": "field", "ip": ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4", "240.0.0.0/4", "::/128", "fc00::/7", "fe80::/10", "ff00::/8"], "outboundTag": "block"},
      {"type": "field", "network": "tcp,udp", "port": "25,465,587,137-139,445", "outboundTag": "block"},
      {"type": "field", "inboundTag": ["personal"], "outboundTag": "direct"}
    ]
  }
}
EOF
}

render_subscription() {
  mkdir -p "$SUB_ROOT"
  chown xray-sub:xray-sub "$SUB_ROOT" 2>/dev/null || true
  chmod 755 "$SUB_ROOT"
  cat > "$SUB_ROOT/$SUB_TOKEN.yaml" <<EOF
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
proxies:
  - name: "Alpine-Xray"
    type: vless
    server: $SERVER_ADDRESS
    port: $PUBLIC_PORT
    uuid: $CLIENT_UUID
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: $REALITY_SERVER_NAME
    client-fingerprint: chrome
    reality-opts:
      public-key: $PUBLIC_KEY
      short-id: $SHORT_ID
proxy-groups:
  - name: PROXY
    type: select
    proxies: ["Alpine-Xray"]
rules:
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF
  chown xray-sub:xray-sub "$SUB_ROOT/$SUB_TOKEN.yaml" 2>/dev/null || true
  chmod 644 "$SUB_ROOT/$SUB_TOKEN.yaml"
}

write_services() {
  cat > /etc/init.d/xray <<EOF
#!/sbin/openrc-run
description="Xray REALITY node"
supervisor="supervise-daemon"
command="$XRAY_RUN"
pidfile="/run/xray.pid"
respawn_delay=5
respawn_max=0
output_log="$XRAY_LOG/output.log"
error_log="$XRAY_LOG/error.log"
depend() { need net; after firewall; }
EOF

  cat > /etc/init.d/xray-sub <<EOF
#!/sbin/openrc-run
description="Xray subscription HTTP"
supervisor="supervise-daemon"
command="$(command -v busybox)"
command_args="httpd -f -p 0.0.0.0:$SUB_LISTEN_PORT -h $SUB_ROOT"
command_user="xray-sub:xray-sub"
pidfile="/run/xray-sub.pid"
respawn_delay=5
respawn_max=0
output_log="$XRAY_LOG/sub.log"
error_log="$XRAY_LOG/sub.err"
depend() { need net; }
EOF
  chmod 755 /etc/init.d/xray /etc/init.d/xray-sub
}

write_admin() {
  cat > "$ADMIN" <<'ADMIN_EOF'
#!/bin/sh
set -eu
STATE=/usr/local/etc/xray/state
SUB_ETC=/etc/xray-sub
case ${1:-} in
  --sub) . "$STATE"; printf 'http://%s:%s/%s.yaml\n' "$SERVER_ADDRESS" "$SUB_PUBLIC_PORT" "$(cat "$SUB_ETC/token")"; exit;;
  --status) rc-service xray status; exit;;
  --uninstall) ACTION=uninstall;;
esac
. "$STATE"
token=$(cat "$SUB_ETC/token")
status() {
  rc-service xray status || true
  echo
  netstat -ltn 2>/dev/null | grep -E ":(${LISTEN_PORT}|${SUB_LISTEN_PORT}) " || true
  echo "订阅：http://$SERVER_ADDRESS:$SUB_PUBLIC_PORT/$token.yaml"
}
restart() { rc-service xray restart && rc-service xray-sub restart; }
uninstall_node() {
  printf '将停止并删除 Xray 服务与配置。输入 yes 继续: '
  read -r ans || exit 1
  [ "$ans" = yes ] || { echo '已取消'; exit 1; }
  rc-service xray stop >/dev/null 2>&1 || true
  rc-service xray-sub stop >/dev/null 2>&1 || true
  rc-update del xray default >/dev/null 2>&1 || true
  rc-update del xray-sub default >/dev/null 2>&1 || true
  rm -f /etc/init.d/xray /etc/init.d/xray-sub /usr/local/bin/xray /usr/local/bin/xray-run "$0"
  rm -rf /usr/local/etc/xray /usr/local/share/xray /srv/sub
  echo '已卸载；/etc/xray-sub 与 /root/xray-backups 保留。'
  echo '请同时删除各设备上的客户端配置。'
}
case ${ACTION:-menu} in
  uninstall) uninstall_node; exit;;
esac
while :; do
  cat <<MENU

Alpine Xray 管理
  1. 状态与端口
  2. 订阅地址
  3. 重启服务
  4. 卸载
  0. 退出
MENU
  printf '选择: '
  read -r opt || exit 0
  case $opt in
    1) status;;
    2) echo "http://$SERVER_ADDRESS:$SUB_PUBLIC_PORT/$token.yaml";;
    3) restart;;
    4) uninstall_node;;
    0) exit 0;;
    *) echo '无效选项';;
  esac
done
ADMIN_EOF
  chmod 700 "$ADMIN"
}

install_node() {
  need_root
  need_alpine
  ensure_deps
  load_state
  if [ "$NONINTERACTIVE" = 1 ]; then
    [ -n "$SERVER_ADDRESS" ] && [ -n "$PUBLIC_PORT" ] && [ -n "$LISTEN_PORT" ] \
      && [ -n "$SUB_PUBLIC_PORT" ] && [ -n "$SUB_LISTEN_PORT" ] \
      || fail '无人值守模式缺少参数'
    REALITY_DEST=${REALITY_DEST:-www.apple.com:443}
    REALITY_SERVER_NAME=${REALITY_SERVER_NAME:-${REALITY_DEST%:*}}
  else
    SERVER_ADDRESS=$(ask 'VPS 公网 IP 或域名' "${SERVER_ADDRESS:-}") || exit 1
    PUBLIC_PORT=$(ask '代理公网 TCP 端口' "${PUBLIC_PORT:-}") || exit 1
    LISTEN_PORT=$(ask '代理内部 TCP 端口（无 NAT 时与公网相同）' "${LISTEN_PORT:-}") || exit 1
    REALITY_DEST=$(ask 'REALITY 目标 host:port' "${REALITY_DEST:-www.apple.com:443}") || exit 1
    REALITY_SERVER_NAME=$(ask 'REALITY serverName' "${REALITY_SERVER_NAME:-${REALITY_DEST%:*}}") || exit 1
    SUB_PUBLIC_PORT=$(ask '订阅公网 TCP 端口' "${SUB_PUBLIC_PORT:-}") || exit 1
    SUB_LISTEN_PORT=$(ask '订阅内部 TCP 端口（>=1024）' "${SUB_LISTEN_PORT:-}") || exit 1
  fi
  validate
  preflight
  TMPDIR_WORK=$(mktemp -d)
  info '下载并校验 Xray …'
  download_release "$TMPDIR_WORK/xray.zip"
  mkdir -p "$TMPDIR_WORK/core"
  unzip -o "$TMPDIR_WORK/xray.zip" xray -d "$TMPDIR_WORK/core" >/dev/null 2>&1 \
    || busybox unzip -o "$TMPDIR_WORK/xray.zip" xray -d "$TMPDIR_WORK/core" >/dev/null
  [ -x "$TMPDIR_WORK/core/xray" ] || fail '解压后找不到 xray'

  addgroup -S xray 2>/dev/null || true
  adduser -S -D -H -G xray -s /sbin/nologin xray 2>/dev/null || true
  addgroup -S xray-sub 2>/dev/null || true
  adduser -S -D -H -G xray-sub -s /sbin/nologin xray-sub 2>/dev/null || true

  snapshot
  install -d -m 755 /usr/local/bin /usr/local/sbin
  install -d -m 750 -o root -g xray "$XRAY_ETC"
  install -d -m 755 "$XRAY_ASSETS"
  install -d -m 750 -o xray -g xray "$XRAY_LOG"
  install -d -m 750 -o root -g xray-sub "$SUB_ETC"
  if [ -f "$STATE" ]; then
    . "$STATE"
  else
    CLIENT_UUID=$(openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')
    keys=$("$TMPDIR_WORK/core/xray" x25519)
    PRIVATE_KEY=$(printf '%s\n' "$keys" | awk -F': *' '/^Private/ {print $2; exit}')
    PUBLIC_KEY=$(printf '%s\n' "$keys" | awk -F': *' '/^Password/ {print $2; exit}')
    SHORT_ID=$(openssl rand -hex 8)
  fi
  case $PRIVATE_KEY in *[!A-Za-z0-9_-]*|'') fail '私钥格式异常';; esac
  case $PUBLIC_KEY in *[!A-Za-z0-9_-]*|'') fail '公钥格式异常';; esac
  case $SHORT_ID in *[!0-9a-f]*|'') fail 'shortId 格式异常';; esac
  save_state

  render_config "$TMPDIR_WORK/config.json"
  if ! "$TMPDIR_WORK/core/xray" run -test -config "$TMPDIR_WORK/config.json" >"$TMPDIR_WORK/test.log" 2>&1; then
    cat "$TMPDIR_WORK/test.log" >&2 || true
    fail 'Xray 配置校验失败'
  fi

  install -m 755 "$TMPDIR_WORK/core/xray" "$XRAY_BIN"
  cat > "$XRAY_RUN" <<'RUN_EOF'
#!/bin/sh
export GOMEMLIMIT=40MiB
export GOGC=30
export XRAY_LOCATION_ASSET=/usr/local/share/xray
exec /usr/local/bin/xray run -config /usr/local/etc/xray/config.json
RUN_EOF
  chmod 755 "$XRAY_RUN"
  install -m 640 -o root -g xray "$TMPDIR_WORK/config.json" "$XRAY_ETC/config.json"

  if [ ! -s "$SUB_TOKEN_FILE" ]; then
    openssl rand -hex 16 > "$SUB_TOKEN_FILE"
  fi
  chmod 600 "$SUB_TOKEN_FILE"
  printf '%s\n' "$SUB_LISTEN_PORT" > "$SUB_PORT_FILE"
  chmod 644 "$SUB_PORT_FILE"
  SUB_TOKEN=$(cat "$SUB_TOKEN_FILE")
  write_services
  render_subscription
  write_admin

  rc-update add xray default >/dev/null 2>&1 || true
  rc-update add xray-sub default >/dev/null 2>&1 || true
  rc-service xray restart >/dev/null 2>&1 || fail 'Xray 服务启动失败'
  sleep 2
  rc-service xray status >/dev/null 2>&1 || {
    cat "$XRAY_LOG/error.log" 2>/dev/null >&2 || true
    fail 'Xray 未保持运行'
  }
  port_busy "$LISTEN_PORT" || fail 'Xray 已启动但监听端口不存在'
  rc-service xray-sub restart >/dev/null 2>&1 || fail '订阅服务启动失败'
  sleep 1
  curl -fsS --max-time 5 "http://127.0.0.1:$SUB_LISTEN_PORT/$SUB_TOKEN.yaml" >/dev/null \
    || fail '订阅本地自检失败'

  cat <<INFO

============================================================
订阅地址（复制到 FlClash 的“订阅”里）：

  http://$SERVER_ADDRESS:$SUB_PUBLIC_PORT/$SUB_TOKEN.yaml

平台端口映射：
  代理  $PUBLIC_PORT/tcp  ->  实例 $LISTEN_PORT
  订阅  $SUB_PUBLIC_PORT/tcp  ->  实例 $SUB_LISTEN_PORT

节点：VLESS + XTLS Vision + REALITY
目标：$REALITY_DEST
管理：xray-admin
============================================================
INFO
}

verify_node() {
  need_root
  [ -f "$STATE" ] || fail '尚未安装节点'
  load_state
  port=${LISTEN_PORT:-0}
  [ "$port" -gt 0 ] || fail '状态文件缺少端口'
  socks=$((20000 + ($$ % 20000)))
  tmp=$(mktemp -d)
  cat > "$tmp/client.json" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{"tag": "socks", "listen": "127.0.0.1", "port": $socks, "protocol": "socks", "settings": {"udp": false}}],
  "outbounds": [{
    "tag": "proxy", "protocol": "vless",
    "settings": {"vnext": [{"address": "127.0.0.1", "port": $port, "users": [{"id": "$CLIENT_UUID", "encryption": "none", "flow": "xtls-rprx-vision"}]}]},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"serverName": "$REALITY_SERVER_NAME", "fingerprint": "chrome", "publicKey": "$PUBLIC_KEY", "shortId": "$SHORT_ID", "spiderX": "/"}}
  }]
}
EOF
  "$XRAY_BIN" run -c "$tmp/client.json" >"$tmp/log" 2>&1 &
  pid=$!
  i=0
  while [ $i -lt 20 ]; do
    netstat -ltn 2>/dev/null | grep -q ":$socks " && break
    kill -0 "$pid" 2>/dev/null || break
    i=$((i + 1)); sleep 0.25
  done
  if netstat -ltn 2>/dev/null | grep -q ":$socks "; then
    if curl --socks5-hostname "127.0.0.1:$socks" -fsS --max-time 15 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q 'ip='; then
      echo 'PASS: 链路自检通过'
      kill "$pid" 2>/dev/null || true
      rm -rf "$tmp"
      return 0
    fi
    code=$(curl --socks5-hostname "127.0.0.1:$socks" -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$REALITY_SERVER_NAME/" 2>/dev/null || true)
    case $code in
      [1-5][0-9][0-9])
        echo "PASS: 链路自检通过（目标返回 HTTP $code）"
        kill "$pid" 2>/dev/null || true
        rm -rf "$tmp"
        return 0;;
    esac
  fi
  tail -20 "$tmp/log" >&2 || true
  kill "$pid" 2>/dev/null || true
  rm -rf "$tmp"
  fail '链路自检失败；请检查目标站与端口映射'
}

uninstall_node() {
  need_root
  rc-service xray stop >/dev/null 2>&1 || true
  rc-service xray-sub stop >/dev/null 2>&1 || true
  rc-update del xray default >/dev/null 2>&1 || true
  rc-update del xray-sub default >/dev/null 2>&1 || true
  rm -f /etc/init.d/xray /etc/init.d/xray-sub "$XRAY_BIN" "$XRAY_RUN" "$ADMIN"
  rm -rf "$XRAY_ETC" "$XRAY_ASSETS" "$SUB_ROOT"
  if [ "$PURGE" = 1 ]; then
    rm -rf "$SUB_ETC"
    echo '已卸载并删除 /etc/xray-sub'
  else
    echo '已卸载；/etc/xray-sub 与 /root/xray-backups 保留'
  fi
  echo '请同时删除各设备上的客户端配置。'
}

case $ACTION in
  install) install_node;;
  verify) verify_node;;
  uninstall) uninstall_node;;
esac
