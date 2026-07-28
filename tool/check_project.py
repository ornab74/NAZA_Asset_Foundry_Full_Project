#!/usr/bin/env python3
from __future__ import annotations

import ast
import hashlib
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REQUIRED = [
    'pubspec.yaml',
    'lib/main.dart',
    'lib/asset_foundry/app.dart',
    'lib/asset_foundry/models.dart',
    'lib/asset_foundry/services.dart',
    'asset_engine/server.py',
    'asset_engine/runner.py',
    'asset_engine/policy.py',
]

missing = [name for name in REQUIRED if not (ROOT / name).is_file()]
if missing:
    raise SystemExit('Missing required files: ' + ', '.join(missing))

for path in sorted((ROOT / 'asset_engine').glob('*.py')):
    ast.parse(path.read_text(encoding='utf-8'), filename=str(path))

for path in sorted((ROOT / 'lib').rglob('*.dart')):
    text = path.read_text(encoding='utf-8')
    if '\x00' in text:
        raise SystemExit(f'NUL byte in {path}')

manifest = ROOT / 'SOURCE_SHA256.txt'
lines = []
for path in sorted([*ROOT.glob('*.yaml'), *ROOT.glob('*.md'), *(ROOT / 'lib').rglob('*.dart'), *(ROOT / 'asset_engine').glob('*.py')]):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    lines.append(f'{digest}  {path.relative_to(ROOT).as_posix()}')
manifest.write_text('\n'.join(lines) + '\n', encoding='utf-8')
print(f'Project structure valid; wrote {manifest.name} with {len(lines)} hashes.')
