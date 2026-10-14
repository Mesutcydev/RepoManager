#!/usr/bin/env python3
"""Offline source/contract checks. No service requests, secrets or reference writes."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--dependency-checkout', type=Path)
args = parser.parse_args()
failures = []
counts = {'json': 0, 'plist': 0, 'swift': 0}
def check(condition, detail):
    if not condition:
        failures.append(detail)

for directory in ['App', 'ShareExtension', 'Packages/RepoManagerCore/Sources', 'Packages/RepoManagerUI/Sources', 'Docs', 'BrandKit']:
    for path in (ROOT/directory).rglob('*'):
        if not path.is_file():
            continue
        try:
            if path.suffix == '.json':
                json.loads(path.read_text()); counts['json'] += 1
            elif path.suffix in {'.plist', '.entitlements', '.xcprivacy'}:
                plistlib.loads(path.read_bytes()); counts['plist'] += 1
            elif path.suffix == '.swift' and 'RepoManagerCatalog' not in path.parts:
                source = path.read_text(); counts['swift'] += 1
                for pattern, label in [
                    (r'\bimport\s+(CoreAI|MLX|Vision|Whisper|llama)\b', 'excluded runtime'),
                    (r'\b(UserDefaults|NSLog|os_log|Logger)\b|\bprint\s*\(', 'plaintext persistence/log sink'),
                ]:
                    check(not re.search(pattern, source), f'{path.relative_to(ROOT)}: {label}')
                # Only the official OAuth callback may use cleartext, and its
                # listener and strict Host check are confined to IPv4 loopback.
                for literal in re.findall(r'http://[^"\s]*', source):
                    check(path.relative_to(ROOT).as_posix() == 'Packages/RepoManagerCore/Sources/RepoManagerCore/ChatGPTLoopback.swift'
                          and literal.startswith('http://127.0.0.1:'), f'{path.relative_to(ROOT)}: non-TLS URL')
        except Exception as error:
            failures.append(f'{path.relative_to(ROOT)}: parse failed ({type(error).__name__})')

catalog = json.loads((ROOT/'Docs/tool-catalog.json').read_text())['tools']
check(len({t['name'] for t in catalog}) == len(catalog), 'Duplicate tool names')
for tool in catalog:
    check(tool['schema'].get('additionalProperties') is False, f"Unbounded properties: {tool['name']}")
    check(tool['permission'] in {'pull', 'push', 'admin'}, f"Missing role: {tool['name']}")
    if tool['risk'] in {'mutation','consequential','destructive'}:
        check(tool.get('reviewPath') is not None or tool['method'] == 'GRAPHQL', f"Missing review snapshot: {tool['name']}")
    if tool['nativeOnly']:
        check('secret' in tool['name'], f"Unexplained native-only tool: {tool['name']}")
contract = json.loads((ROOT/'Docs/openapi.json').read_text())
check(contract['openapi'] == '3.1.0', 'OpenAPI version')
check(not any('approve' in path for path in contract['paths']), 'Remote approval route')
check(bool(contract['security']), 'API authentication missing')

main = plistlib.loads((ROOT/'App/RepoManager.entitlements').read_bytes())
share = plistlib.loads((ROOT/'ShareExtension/RepoManagerShare.entitlements').read_bytes())
check(main['com.apple.security.application-groups'] == ['group.com.mesutcydev.repomanager'], 'App group identity')
check(main['com.apple.developer.icloud-container-identifiers'] == ['iCloud.com.mesutcydev.repomanager'], 'CloudKit identity')
check(set(share) == {'com.apple.security.application-groups'}, 'Share extension privilege expansion')
check('NSCameraUsageDescription' not in plistlib.loads((ROOT/'App/Info.plist').read_bytes()), 'Camera permission')

provenance = json.loads((ROOT/'Docs/DEPENDENCY_PROVENANCE.json').read_text())
resolved = json.loads((ROOT/'Packages/RepoManagerCore/Package.resolved').read_text())
pin = next(p for p in resolved['pins'] if p['identity'] == 'swift-sodium')
check(pin['state']['version'] == '0.11.0' and pin['state']['revision'] == provenance['revision'], 'Sodium pin mismatch')
dependency_status = 'not inspected; pass --dependency-checkout for resolved binary verification'
if args.dependency_checkout:
    for name, digest in provenance['files'].items():
        path = args.dependency_checkout/name
        check(path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == digest, f'Dependency mismatch: {name}')
    dependency_status = f"{len(provenance['files'])} recorded dependency files checked"
for name in ['LICENSE', 'LICENSES/Swift-Sodium-0.11.0-ISC.txt', 'LICENSES/libsodium-1.0.22-ISC.txt', 'App/Resources/ThirdPartyNotices.txt']:
    check((ROOT/name).is_file(), f'Missing license: {name}')
print(json.dumps({'passed': not failures, 'counts': counts, 'tools': len(catalog), 'routes': sum(len(v) for v in contract['paths'].values()), 'dependency': dependency_status, 'failures': failures}, indent=2))
raise SystemExit(1 if failures else 0)
