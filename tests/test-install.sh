#!/bin/sh
# Run only inside a disposable Alpine container with network access.
set -eu
[ -f /DISPOSABLE_ALPINE_TEST ] || { echo 'SKIP: disposable Alpine container required'; exit 0; }
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

export NONINTERACTIVE=1
export SERVER_ADDRESS=203.0.113.10
export PUBLIC_PORT=28443 LISTEN_PORT=18443
export SUB_PUBLIC_PORT=28996 SUB_LISTEN_PORT=18996

sh alpine-singbox.sh --yes --target www.apple.com:443 >/tmp/install.log 2>&1 || {
  cat /tmp/install.log; exit 1;
}
[ -s /etc/sing-box/config.json ] || { echo 'FAIL: config missing'; exit 1; }
[ -s /etc/sing-box/state ] || { echo 'FAIL: state missing'; exit 1; }
sing-box check -C /etc/sing-box || { echo 'FAIL: config invalid'; exit 1; }
netstat -ltn | grep -q ':18443 ' || { echo 'FAIL: proxy port not listening'; exit 1; }
netstat -ltn | grep -q ':18996 ' || { echo 'FAIL: subscription port not listening'; exit 1; }

token=$(cat /etc/singbox-sub/token)
curl -fsS "http://127.0.0.1:18996/$token.yaml" >/tmp/sub.yaml || { echo 'FAIL: subscription not served'; exit 1; }
grep -q 'flow: xtls-rprx-vision' /tmp/sub.yaml || { echo 'FAIL: Vision missing'; exit 1; }
grep -q 'reality-opts:' /tmp/sub.yaml || { echo 'FAIL: REALITY missing'; exit 1; }

sh alpine-singbox.sh --verify || { echo 'FAIL: end-to-end verify'; exit 1; }

before=$(sha256sum /etc/sing-box/state /etc/sing-box/config.json)
sh alpine-singbox.sh --yes --target www.apple.com:443 >/tmp/reinstall.log 2>&1 || {
  cat /tmp/reinstall.log; exit 1;
}
after=$(sha256sum /etc/sing-box/state /etc/sing-box/config.json)
[ "$before" = "$after" ] || { echo 'FAIL: reinstall changed keys or config'; exit 1; }
netstat -ltn | grep -q ':18443 ' || { echo 'FAIL: proxy port lost after reinstall'; exit 1; }

printf 'yes\n' | sh alpine-singbox.sh --uninstall >/tmp/uninstall.log 2>&1
[ ! -e /etc/sing-box/config.json ] || { echo 'FAIL: config survived uninstall'; exit 1; }
[ ! -e /etc/init.d/sbox ] || { echo 'FAIL: service survived uninstall'; exit 1; }
[ -d /etc/singbox-sub ] || { echo 'FAIL: subscription state not preserved'; exit 1; }
[ -d /root/singbox-backups ] || { echo 'FAIL: backups not preserved'; exit 1; }

echo 'PASS: install, subscription, verify, idempotent reinstall and uninstall'
