#!/bin/sh
# Run only inside a disposable Alpine container with network access.
set -eu
[ -f /DISPOSABLE_ALPINE_TEST ] || { echo 'SKIP: disposable Alpine container required'; exit 0; }
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

export NONINTERACTIVE=1
export SERVER_ADDRESS=203.0.113.10
export PUBLIC_PORT=28443 LISTEN_PORT=18443
export SUB_PUBLIC_PORT=28996 SUB_LISTEN_PORT=80
export PLAN_TOTAL=100GB PLAN_RESET_DAY=17 PLAN_EXPIRE=2027-12-31

sh alpine-singbox.sh --yes --target www.apple.com:443 >/tmp/install.log 2>&1 || {
  cat /tmp/install.log; exit 1;
}
[ -s /etc/sing-box/config.json ] || { echo 'FAIL: config missing'; exit 1; }
[ -s /etc/sing-box/state ] || { echo 'FAIL: state missing'; exit 1; }
sing-box check -C /etc/sing-box || { echo 'FAIL: config invalid'; exit 1; }
netstat -ltn | grep -q ':18443 ' || { echo 'FAIL: proxy port not listening'; exit 1; }
netstat -ltn | grep -q ':80 ' || { echo 'FAIL: subscription port not listening'; exit 1; }
sub_pid=$(cat /run/sb-sub.pid)
[ "$(awk '/^Uid:/ {print $2}' "/proc/$sub_pid/status")" = "$(id -u sbsub)" ] \
  || { echo 'FAIL: subscription service did not drop privileges'; exit 1; }

token=$(cat /etc/singbox-sub/token)
sub_url="http://127.0.0.1:80/cgi-bin/$token"
curl -fsS -D /tmp/sub.headers "$sub_url" >/tmp/sub.yaml || { echo 'FAIL: subscription not served'; exit 1; }
curl -fsS "http://127.0.0.1:80/$token.yaml" >/tmp/legacy-sub.yaml || { echo 'FAIL: legacy subscription URL not served'; exit 1; }
cmp /tmp/sub.yaml /tmp/legacy-sub.yaml || { echo 'FAIL: legacy URL returned a different subscription'; exit 1; }
[ "$(sb-admin --sub)" = "http://203.0.113.10:28996/cgi-bin/$token" ] \
  || { echo 'FAIL: admin printed an incorrect subscription URL'; exit 1; }
grep -q 'flow: xtls-rprx-vision' /tmp/sub.yaml || { echo 'FAIL: Vision missing'; exit 1; }
grep -q 'reality-opts:' /tmp/sub.yaml || { echo 'FAIL: REALITY missing'; exit 1; }
[ "$(grep -c '^- ' /tmp/sub.yaml)" -eq 8626 ] || { echo 'FAIL: full public rules missing'; exit 1; }
expire_epoch=$(date -u -d '2027-12-31 23:59:59' +%s)
grep -qi "^Subscription-Userinfo: upload=0; download=0; total=107374182400; expire=$expire_epoch" /tmp/sub.headers \
  || { echo 'FAIL: subscription quota header missing'; exit 1; }
grep -qi '^Profile-Update-Interval: 24' /tmp/sub.headers || { echo 'FAIL: profile refresh interval missing'; exit 1; }
sb-admin --plan >/tmp/plan.log
grep -q '月流量：100GB' /tmp/plan.log || { echo 'FAIL: plan total missing'; exit 1; }
grep -q '重置日：每月 17 日' /tmp/plan.log || { echo 'FAIL: plan reset day missing'; exit 1; }
grep -q '到期日：2027-12-31' /tmp/plan.log || { echo 'FAIL: plan expiry missing'; exit 1; }
printf '123\n456\n' | sb-admin --quota >/tmp/quota.log
curl -fsS -D /tmp/sub.headers "$sub_url" >/tmp/sub.yaml
grep -qi "^Subscription-Userinfo: upload=123; download=456; total=107374182400; expire=$expire_epoch" /tmp/sub.headers \
  || { echo 'FAIL: manual usage snapshot missing from subscription'; exit 1; }
if [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:80/cgi-bin/not-the-token")" != 404 ]; then
  echo 'FAIL: unknown subscription token was served'; exit 1
fi
# Only test containers install Python/YAML; production needs neither.
python3 tests/check-profile.py /tmp/sub.yaml /etc/sing-box/state rules.template.yaml
cp /etc/singbox-sub/token /tmp/token-before
# Simulate a local-only override file: it must never be auto-published.
printf '%s\n' '- DOMAIN,private-device.example.invalid,DIRECT' > /etc/singbox-sub/private-rules.yaml
sb-admin --update-sub >/tmp/update.log
curl -fsS "$sub_url" >/tmp/sub.yaml
if grep -q 'private-device.example.invalid' /tmp/sub.yaml; then echo 'FAIL: private rule merged'; exit 1; fi

sh alpine-singbox.sh --verify || { echo 'FAIL: end-to-end verify'; exit 1; }

# A public edit survives reinstall and is served after regeneration.
sed '1i\- DOMAIN,edited.example.invalid,DIRECT' /etc/singbox-sub/rules.yaml >/tmp/custom-rules
cat /tmp/custom-rules > /etc/singbox-sub/rules.yaml
sb-admin --update-sub >/tmp/update.log
curl -fsS "$sub_url" >/tmp/before.yaml
python3 tests/check-profile.py /tmp/before.yaml /etc/sing-box/state /etc/singbox-sub/rules.yaml
before=$(sha256sum /etc/sing-box/state /etc/sing-box/config.json /etc/singbox-sub/rules.yaml)
sh alpine-singbox.sh --yes --target www.apple.com:443 >/tmp/reinstall.log 2>&1 || {
  cat /tmp/reinstall.log; exit 1;
}
after=$(sha256sum /etc/sing-box/state /etc/sing-box/config.json /etc/singbox-sub/rules.yaml)
cmp /tmp/token-before /etc/singbox-sub/token
curl -fsS "$sub_url" >/tmp/after.yaml
cmp /tmp/before.yaml /tmp/after.yaml
# Invalid edits cannot replace the served subscription, either via admin or reinstall.
printf '%s\n' 'proxies: []' > /etc/singbox-sub/rules.yaml
if sb-admin --update-sub >/tmp/bad-rules.log 2>&1; then echo 'FAIL: invalid rules updated'; exit 1; fi
curl -fsS "$sub_url" >/tmp/after-invalid.yaml
cmp /tmp/before.yaml /tmp/after-invalid.yaml
if sh alpine-singbox.sh --yes >/tmp/bad-reinstall.log 2>&1; then echo 'FAIL: invalid rules reinstalled'; exit 1; fi
curl -fsS "$sub_url" >/tmp/after-failed-install.yaml
cmp /tmp/before.yaml /tmp/after-failed-install.yaml
cat /tmp/custom-rules > /etc/singbox-sub/rules.yaml
[ "$before" = "$after" ] || { echo 'FAIL: reinstall changed keys or config'; exit 1; }
netstat -ltn | grep -q ':18443 ' || { echo 'FAIL: proxy port lost after reinstall'; exit 1; }

printf 'yes\n' | sh alpine-singbox.sh --uninstall >/tmp/uninstall.log 2>&1
[ ! -e /etc/sing-box/config.json ] || { echo 'FAIL: config survived uninstall'; exit 1; }
[ ! -e /etc/init.d/sbox ] || { echo 'FAIL: service survived uninstall'; exit 1; }
[ -d /etc/singbox-sub ] || { echo 'FAIL: subscription state not preserved'; exit 1; }
[ -d /root/singbox-backups ] || { echo 'FAIL: backups not preserved'; exit 1; }

echo 'PASS: install, subscription, verify, idempotent reinstall and uninstall'
