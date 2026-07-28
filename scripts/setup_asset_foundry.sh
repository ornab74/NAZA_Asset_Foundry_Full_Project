#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="${ASSET_FOUNDRY_VENV:-$ROOT/.asset-foundry-venv}"
PYTHON="${PYTHON:-python3}"

"$PYTHON" -m venv "$VENV"
"$VENV/bin/python" -m pip install --upgrade pip
"$VENV/bin/python" -m pip install -r "$ROOT/asset_engine/requirements.txt"

cat <<INFO
Asset Foundry Python environment is ready:
  $VENV

Recommended system tools:
  Blender:    $(command -v blender || echo 'not found')
  bubblewrap: $(command -v bwrap || echo 'not found; install for stronger Linux isolation')
  ffmpeg:     $(command -v ffmpeg || echo 'not found')

Run Flutter with:
  export PATH="$ROOT/.tooling/flutter/bin:\$PATH"
  export PUB_CACHE="$ROOT/.pub-cache"
  flutter pub get
  flutter run -t lib/asset_foundry_main.dart \
    --dart-define=ASSET_FOUNDRY_PYTHON="$VENV/bin/python"

Set the Python executable in the app Settings page to:
  $VENV/bin/python
INFO
