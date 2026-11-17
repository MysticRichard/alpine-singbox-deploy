#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
script=${ALPINE_SCRIPT:-"$root/alpine-singbox.sh"}
sed '/^case $ACTION in/,$d' "$script" > "$work/functions.sh"

run_plan() {
  env -i PATH="$PATH" NONINTERACTIVE=1 PLAN_TOTAL="$1" PLAN_RESET_DAY="$2" PLAN_EXPIRE="$3" \
    sh -c 'functions=$1; set --; . "$functions"; validate_plan; printf "%s|%s|%s|%s\n" "$PLAN_TOTAL" "$PLAN_TOTAL_BYTES" "$PLAN_RESET_DAY" "$PLAN_EXPIRE_EPOCH"' \
    sh "$work/functions.sh"
}

expected_expire=$(date -u -d '2027-12-31 23:59:59' +%s)
[ "$(run_plan 100GB 17 2027-12-31)" = "100GB|107374182400|17|$expected_expire" ]
[ "$(run_plan 1.5GB 0 0)" = '1.5GB|1610612736|0|0' ]

while IFS=' ' read -r total reset expire; do
  if run_plan "$total" "$reset" "$expire" >/dev/null 2>&1; then
    echo "FAIL: accepted invalid provider plan: $total $reset $expire" >&2
    exit 1
  fi
done <<'INVALID'
100XB 1 0
100GB 32 0
100GB 1 2027-02-30
INVALID

echo 'PASS: provider plan values and invalid inputs'
