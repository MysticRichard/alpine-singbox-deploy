#!/usr/bin/env python3
"""Bundle reviewed public rules and the subscription updater into one installer."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
source = (ROOT / 'src/alpine-singbox.sh.in').read_text(encoding='utf-8')
rules = (ROOT / 'rules.template.yaml').read_text(encoding='utf-8')
assert '__ALPINE_PUBLIC_RULES__' not in rules
assert len([line for line in rules.splitlines() if line.startswith('- ')]) == 8633
assert rules.rstrip().endswith('- MATCH,PROXY')


def function(name):
    start = source.index(name + '() {\n')
    # These shared functions contain no column-zero heredoc braces.
    end = source.index('\n}\n', start) + 3
    return source[start:end]


helper = '#!/bin/sh\nset -eu\numask 077\n'
helper += source[source.index('SB_ETC='):source.index('fail() {')]
helper += "fail() { printf 'ERROR: %s\\n' \"$*\" >&2; exit 1; }\n"
for name in ('valid_port', 'valid_host', 'load_state', 'validate', 'validate_rules', 'render_subscription'):
    helper += function(name) + '\n'
helper += 'load_state\nvalidate\nSUB_TOKEN=$(cat "$SUB_TOKEN_FILE")\nrender_subscription\n'
helper += "printf '订阅已更新：%s 条公共规则。请在 FlClash 刷新订阅。\\n' \"$(grep -c '^- ' \"$RULES\")\"\n"
result = source.replace('__PUBLIC_RULES__', "  cat <<'__ALPINE_PUBLIC_RULES__'\n" + rules.rstrip() + '\n__ALPINE_PUBLIC_RULES__')
result = result.replace('__SUB_TOOL__', "  cat <<'__ALPINE_SUB_TOOL__'\n" + helper.rstrip() + '\n__ALPINE_SUB_TOOL__')
assert '__SUB_TOOL__' not in result and '__PUBLIC_RULES__' not in result
out = ROOT / 'alpine-singbox.sh'
if '--check' in sys.argv:
    assert out.read_text(encoding='utf-8') == result, 'Generated installer is stale; run python3 build.py'
    print('PASS: single-file bundle matches source and public rules')
else:
    out.write_bytes(result.encode('utf-8'))
    print('Built alpine-singbox.sh (8633 public rules; private overrides excluded)')
