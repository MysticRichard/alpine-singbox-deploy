#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)

docker run --rm -v "$root:/work:ro" alpine:3.23 sh -n /work/alpine-singbox.sh
echo 'PASS: Alpine ash syntax'

docker run --rm --init -v "$root:/work" --privileged alpine:3.23 sh -c '
  apk add --no-cache openrc >/dev/null 2>&1
  mkdir -p /run/openrc; touch /run/openrc/softlevel
  touch /DISPOSABLE_ALPINE_TEST
  cd /work && sh tests/test-install.sh
'
echo 'PASS: all Alpine tests'
