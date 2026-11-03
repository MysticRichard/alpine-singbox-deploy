#!/bin/sh
# Isolated subscription checks; no installed services or user data touched.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed '/^case \$ACTION in/,$d' "$root/alpine-singbox.sh" > "$work/functions.sh"
export NONINTERACTIVE=1
# shellcheck disable=SC1091
. "$work/functions.sh"
SUB_ETC=$work/state
SUB_ROOT=$work/web
RULES=$SUB_ETC/rules.yaml
mkdir -p "$SUB_ETC" "$SUB_ROOT"
SERVER_ADDRESS=203.0.113.10
PUBLIC_PORT=28443
CLIENT_UUID=11111111-1111-4111-8111-111111111111
PUBLIC_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
SHORT_ID=1234567890123456
REALITY_SERVER_NAME=example.com
SUB_TOKEN=0123456789abcdef0123456789abcdef

seed_rules
cmp "$RULES" "$root/rules.template.yaml"
[ "$(grep -c '^- ' "$RULES")" -eq 8626 ]
render_subscription
sed -n '/^rules:$/,$p' "$SUB_ROOT/$SUB_TOKEN.yaml" | sed '1d' > "$work/rendered"
grep '^- ' "$RULES" > "$work/expected"
cmp "$work/expected" "$work/rendered"
# Synthetic public edits survive seeding/reinstallation and affect regeneration.
sed '1i\- DOMAIN,edited.example.invalid,DIRECT' "$RULES" > "$work/custom"
cp "$work/custom" "$RULES"
seed_rules
cmp "$work/custom" "$RULES"
render_subscription
grep -q 'edited.example.invalid' "$SUB_ROOT/$SUB_TOKEN.yaml"
cp "$SUB_ROOT/$SUB_TOKEN.yaml" "$work/before"
cp "$RULES" "$work/good-rules"
for bad in 'proxies: []' '- DOMAIN,example.com,missing-policy' '- MATCH,DIRECT' '- DOMAIN,example.com,PROXY # injected' '' \
  '- IP-CIDR,not-a-cidr,DIRECT,no-resolve' '- IP-CIDR,999.1.1.1/24,DIRECT' \
  '- IP-CIDR,1.1.1.1/33,DIRECT' '- IP-CIDR6,gggg::/64,DIRECT' '- IP-CIDR6,fd00::/129,DIRECT' \
  '- DOMAIN,,DIRECT' '- GEOIP,INVALID,DIRECT' '- AND,invalid,DIRECT'; do
  printf '%s\n' "$bad" > "$RULES"
  case $bad in '- IP-'*|'- DOMAIN,,DIRECT'|'- GEOIP,INVALID,DIRECT'|'- AND,invalid,DIRECT') printf '%s\n' '- MATCH,PROXY' >> "$RULES";; esac
  if (render_subscription) >/dev/null 2>&1; then echo 'FAIL: invalid rules accepted'; exit 1; fi
  cmp "$work/before" "$SUB_ROOT/$SUB_TOKEN.yaml"
done
cp "$work/good-rules" "$RULES"
printf '%s\n' '- DOMAIN,after-match.example.invalid,PROXY' >> "$RULES"
if (render_subscription) >/dev/null 2>&1; then echo 'FAIL: rule after MATCH accepted'; exit 1; fi
cmp "$work/before" "$SUB_ROOT/$SUB_TOKEN.yaml"
cp "$work/good-rules" "$RULES"
render_subscription
# A file containing client-only private overrides is never automatically merged.
printf '%s\n' '- DOMAIN,private-device.example.invalid,DIRECT' > "$SUB_ETC/private-rules.yaml"
render_subscription
if grep -q 'private-device.example.invalid' "$SUB_ROOT/$SUB_TOKEN.yaml"; then exit 1; fi
# Numeric short IDs must remain strings in YAML.
grep -q 'short-id: "1234567890123456"' "$SUB_ROOT/$SUB_TOKEN.yaml"
echo 'PASS: 8626 public rules in order; edits retained; atomic updates reject bad rules; no private-file merge'
