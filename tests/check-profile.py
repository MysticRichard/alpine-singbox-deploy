"""Parse the actually served profile and compare every rule in order."""
import sys
from pathlib import Path
import yaml

profile = yaml.safe_load(Path(sys.argv[1]).read_text())
state = dict(line.split('=', 1) for line in Path(sys.argv[2]).read_text().splitlines())
rules = yaml.safe_load(Path(sys.argv[3]).read_text())
assert profile['rules'] == rules, 'Public rules lost, reordered or supplemented'
assert rules[-1] == 'MATCH,PROXY'
assert rules.count('MATCH,PROXY') == 1
node = profile['proxies'][0]
assert node['flow'] == 'xtls-rprx-vision'
assert node['reality-opts']['short-id'] == state['SHORT_ID']
assert isinstance(node['reality-opts']['short-id'], str)
assert state['PRIVATE_KEY'] not in Path(sys.argv[1]).read_text()
assert node['port'] == int(state['PUBLIC_PORT'])
for rule in rules:
    fields = rule.split(',')
    policy = fields[-2] if fields[-1] == 'no-resolve' else fields[-1]
    assert policy in ('DIRECT', 'PROXY', 'REJECT'), 'Unknown policy'
print(f'PASS: served YAML has {len(rules)} ordered rules, valid policies and no server private key')
