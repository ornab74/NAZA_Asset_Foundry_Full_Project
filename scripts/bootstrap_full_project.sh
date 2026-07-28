#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v flutter >/dev/null || { echo 'Flutter is required on PATH.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3 is required on PATH.' >&2; exit 1; }

# Preserve authored source while Flutter creates missing host platform shells.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -a lib pubspec.yaml analysis_options.yaml "$TMP/"
flutter create --no-pub \
  --project-name naza_asset_foundry \
  --org com.naza \
  --platforms android,linux,windows,macos,ios,web .
rm -rf lib
cp -a "$TMP/lib" ./lib
cp "$TMP/pubspec.yaml" pubspec.yaml
cp "$TMP/analysis_options.yaml" analysis_options.yaml

flutter pub get
python3 -m venv .asset-foundry-venv
.asset-foundry-venv/bin/python -m pip install --upgrade pip
.asset-foundry-venv/bin/python -m pip install -r asset_engine/requirements.txt
.asset-foundry-venv/bin/python -m unittest asset_engine.test_policy -v
python3 tool/check_project.py

echo
echo 'NAZA Asset Foundry is ready.'
echo 'Run: ./scripts/run_asset_foundry.sh'
