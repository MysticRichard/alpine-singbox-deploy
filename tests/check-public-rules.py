"""Guard the reviewed public snapshot; private originals never enter this repo."""
from pathlib import Path
from ipaddress import ip_network
import hashlib
import re

root = Path(__file__).resolve().parent.parent
raw = (root / 'rules.template.yaml').read_bytes()
assert hashlib.sha256(raw).hexdigest() == 'b284b1a909b8edcac96db1b07f384dd875e134e199b98ec3f7615200133d6bd1'
rules = [line[2:] for line in raw.decode().splitlines() if line.startswith('- ')]
assert len(rules) == 8633
# Public tracker from the existing template, not a personal DDNS endpoint.
public_ddns = {'tr4ck3r.duckdns.org'}
for number, rule in enumerate(rules, 1):
    fields = rule.split(',')
    if fields[0] in ('DOMAIN', 'DOMAIN-SUFFIX'):
        value = fields[1].lower()
        personal_namespace = any(value.endswith('.' + suffix) for suffix in (
            'duckdns.org', 'ts.net', 'synology.me', 'myqnapcloud.com', 'ddns.net', 'ddns.org'))
        assert not personal_namespace or value in public_ddns, f'Review DDNS/device domain at public rule {number}'
    if fields[0] in ('IP-CIDR', 'IP-CIDR6'):
        network = ip_network(fields[1], strict=False)
        # Generic reserved ranges are public routing defaults; individual LAN/CGNAT
        # device addresses require private handling. Loopback ::1 is generic.
        device_space = any(network.version == area.version and network.subnet_of(area) for area in map(ip_network, (
            '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '100.64.0.0/10', 'fc00::/7')))
        # ACL4SSR/Clash/Ruleset/TeamViewer.list contains this service-wide
        # address; it is not an individual device belonging to the user.
        public_service = network == ip_network('172.16.102.56/32')
        assert not (device_space and network.prefixlen == network.max_prefixlen and not public_service), f'Review private host at public rule {number}'
assert rules[-1] == 'MATCH,PROXY'
for file in (root / 'src/alpine-singbox.sh.in', root / 'alpine-singbox.sh'):
    text = file.read_text(encoding='utf-8')
    assert not re.search(r'ghp_[A-Za-z0-9]{20,}|BEGIN [A-Z ]*PRIVATE KEY', text)
print('PASS: reviewed public snapshot, generic private ranges retained, no individual LAN/CGNAT devices')
