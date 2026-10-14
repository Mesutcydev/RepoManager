#!/usr/bin/env python3
"""Package current build sources for review; never creates/publishes a repository."""
import argparse
from datetime import date, datetime
import hashlib
import json
from pathlib import Path
import re
import zipfile
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=ROOT/'dist/RepoManager-source.zip')
parser.add_argument('--date', type=date.fromisoformat, default=datetime.now(ZoneInfo('Europe/Istanbul')).date())
args = parser.parse_args()
if not 1980 <= args.date.year <= 2107:
    raise SystemExit('The ZIP date must be between 1980 and 2107.')
trees = ['App', 'ShareExtension', 'Tests', 'Packages/RepoManagerCore/Sources',
         'Packages/RepoManagerCore/Tests', 'Packages/RepoManagerUI/Sources', 'LICENSES', 'BrandKit/Assets']
single_files = ['LICENSE', 'SETUP.md', 'ARCHITECTURE.md', 'PRIVACY.md', 'CONTRIBUTING.md', 'BrandKit/README.md',
                'THIRD_PARTY_NOTICES.md', 'project.yml', '.gitignore', 'BrandKit/colors.json', 'BrandKit/contrast.json',
                'Docs/Design/REPOSITORY_CASE_PROMPT.txt',
                'Packages/RepoManagerCore/Package.swift', 'Packages/RepoManagerCore/Package.resolved',
                'Packages/RepoManagerUI/Package.swift']
public_docs = ['CAPABILITIES.md', 'TOOL_CATALOG.md', 'REASONING.md', 'SPECIFICATION.md',
               'CHATGPT_SIGN_IN.md', 'OPEN_SOURCE_RELEASE.md', 'PUBLIC_README.md', 'GITHUB_APP_SETUP.md', 'MONETIZATION.md',
               'PROVENANCE.json', 'DEPENDENCY_PROVENANCE.json', 'REFERENCE_BASELINE.json',
               'tool-catalog.json', 'openapi.json']
public_scripts = ['validate_project.py', 'validate_github_configuration.sh',
                  'validate_chatgpt_configuration.sh', 'generate_contracts.py', 'prepare_open_source.py']
paths = {ROOT/name for name in single_files}
paths.update(ROOT/'Docs'/name for name in public_docs)
paths.update(ROOT/'scripts'/name for name in public_scripts)
for name in trees:
    paths.update(path for path in (ROOT/name).rglob('*') if path.is_file())
excluded_parts = {'.git', '.build', '.swiftpm', '__pycache__', 'DerivedData', 'xcuserdata'}
excluded_suffixes = {'.p8', '.p12', '.pem', '.key', '.mobileprovision', '.ipa', '.rmbundle', '.rmvault', '.xcuserstate'}
entries = {'README.md': (ROOT/'Docs/PUBLIC_README.md').read_bytes()}
for path in sorted(paths):
    relative = path.relative_to(ROOT)
    if any(part in excluded_parts for part in relative.parts) or path.suffix in excluded_suffixes or path.name.startswith('.env'):
        continue
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f'Missing or symlinked public source: {relative}')
    data = path.read_bytes()
    if path.suffix in {'.swift', '.md', '.json', '.plist', '.yml', '.py', '.sh'}:
        # High-confidence literal credentials only; public client IDs, code
        # patterns and synthetic signature fixtures are not account secrets.
        for pattern in [rb'-----BEGIN (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----',
                        rb'sk-proj-[A-Za-z0-9_-]{30,}', rb'github_pat_[A-Za-z0-9_]{50,}']:
            if re.search(pattern, data):
                raise SystemExit(f'Review possible credential in {relative}; source package not written.')
    entries[relative.as_posix()] = data
manifest = {
    'prepared_on': args.date.isoformat(), 'license': 'MIT', 'app_price': 'Free',
    'public_repository': None, 'publication_status': 'Prepared locally; not published',
    'monetization_status': 'Optional one-time Pro API-provider unlock planned; not implemented or offered',
    'files': {name: hashlib.sha256(data).hexdigest() for name, data in sorted(entries.items())},
    'excluded': ['Git history', 'compiler/package caches', 'signing files', 'QA logs and screenshots',
                 'TestFlight receipts', 'App Store account/evidence files'],
}
entries['SOURCE_MANIFEST.json'] = (json.dumps(manifest, indent=2, sort_keys=True)+'\n').encode()
output = args.output.resolve()
output.parent.mkdir(parents=True, exist_ok=True)
temporary = output.with_suffix('.tmp')
with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for name, data in sorted(entries.items()):
        info = zipfile.ZipInfo('RepoManager/'+name, date_time=(args.date.year, args.date.month, args.date.day, 0, 0, 0))
        info.create_system = 3
        info.external_attr = (0o100755 if name.endswith('.sh') else 0o100644) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, data)
temporary.replace(output)
with zipfile.ZipFile(output) as archive:
    if archive.testzip() is not None or len(archive.namelist()) != len(entries):
        raise SystemExit('Source archive validation failed.')
print(json.dumps({'output': str(output), 'files': len(entries), 'bytes': output.stat().st_size,
                  'sha256': hashlib.sha256(output.read_bytes()).hexdigest(), 'published': False}, indent=2))
