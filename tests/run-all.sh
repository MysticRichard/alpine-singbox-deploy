#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)

docker run --rm -v "$root:/work:ro" -w /work python:3.11-slim python build.py --check
docker run --rm -v "$root:/work:ro" -w /work python:3.11-slim python tests/check-public-rules.py
docker run --rm -v "$root:/work:ro" alpine:3.23 sh /work/tests/test-rules.sh
docker run --rm -v "$root:/work:ro" alpine:3.23 sh -n /work/alpine-singbox.sh
echo 'PASS: Alpine ash syntax'

docker run --rm --init -v "$root:/work" --privileged alpine:3.23 sh -c '
  apk add --no-cache openrc python3 py3-yaml >/dev/null 2>&1
  mkdir -p /run/openrc; touch /run/openrc/softlevel
  touch /DISPOSABLE_ALPINE_TEST
  cd /work && sh tests/test-install.sh
'
echo 'PASS: all Alpine tests'
