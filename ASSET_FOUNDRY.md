# NAZA Asset Foundry

NAZA Asset Foundry is a dedicated Flutter/Dart surface inside this repository
for generating local, editable, rigged game assets from text or reference images.
It combines GPT-5.6 codecell design, GPT Image reference generation, a database
of plans and artifacts, NumPy/OpenCV processing, topology and rigging workflows,
and optional headless Blender compilation.

The central rule is simple: **GPT may write custom Python, but it may not execute
that Python until a human reviews the full cell in a popup and approves the exact
SHA-256 hash and capability list.** Rewriting a cell invalidates approval.

## Start

```bash
./scripts/setup_asset_foundry.sh
export PATH="$PWD/.tooling/flutter/bin:$PATH"
export PUB_CACHE="$PWD/.pub-cache"
flutter pub get
flutter run -t lib/asset_foundry_main.dart
```

Windows PowerShell:

```powershell
.\scripts\setup_asset_foundry.ps1
flutter pub get
flutter run -t lib/asset_foundry_main.dart
```

Then open **Settings** and configure:

- OpenAI API key (AES-256-GCM encrypted at rest),
- planner model, default `gpt-5.6`,
- image model, default `gpt-image-1`,
- Python executable from the dedicated virtual environment,
- Blender executable,
- loopback engine port,
- optional fail-closed bubblewrap requirement.

See [`docs/asset-foundry-codecells.md`](docs/asset-foundry-codecells.md) for the
architecture, approval protocol, database model, notebook lineage, and research
paradigm mapping. See [`asset_engine/README.md`](asset_engine/README.md) for the
local execution engine and security boundaries.
