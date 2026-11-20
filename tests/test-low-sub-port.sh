#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
NONINTERACTIVE=1
export NONINTERACTIVE
sed '/^case $ACTION in/,$d' "$root/alpine-singbox.sh" > "$work/functions.sh"
# shellcheck disable=SC1091
. "$work/functions.sh"
SERVER_ADDRESS=203.0.113.10
PUBLIC_PORT=28443
LISTEN_PORT=18443
SUB_PUBLIC_PORT=28996
SUB_LISTEN_PORT=80
REALITY_DEST=www.apple.com:443
REALITY_SERVER_NAME=www.apple.com
validate
SERVER_ADDRESS=2001:db8::10
validate
if (SERVER_ADDRESS=2001:db8:::10; validate) 2>/dev/null; then
  echo 'FAIL: malformed IPv6 address accepted'
  exit 1
fi
echo 'PASS: subscription internal port 80 is accepted'
