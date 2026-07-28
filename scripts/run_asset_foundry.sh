#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PYTHON="$ROOT/.asset-foundry-venv/bin/python"
[[ -x "$PYTHON" ]] || { echo 'Run scripts/bootstrap_full_project.sh first.' >&2; exit 1; }
DEVICE="${FLUTTER_DEVICE:-linux}"
exec flutter run -d "$DEVICE" \
  --dart-define="ASSET_FOUNDRY_PYTHON=$PYTHON" \
  --dart-define="ASSET_FOUNDRY_ENGINE_SCRIPT=$ROOT/asset_engine/server.py" \
  --dart-define="ASSET_FOUNDRY_BLENDER=${ASSET_FOUNDRY_BLENDER:-blender}"
