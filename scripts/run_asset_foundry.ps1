$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root
$Python = Join-Path $Root '.asset-foundry-venv\Scripts\python.exe'
if (-not (Test-Path $Python)) { throw 'Run scripts\bootstrap_full_project.ps1 first.' }
$Device = if ($env:FLUTTER_DEVICE) { $env:FLUTTER_DEVICE } else { 'windows' }
$Blender = if ($env:ASSET_FOUNDRY_BLENDER) { $env:ASSET_FOUNDRY_BLENDER } else { 'blender' }
flutter run -d $Device `
  --dart-define="ASSET_FOUNDRY_PYTHON=$Python" `
  --dart-define="ASSET_FOUNDRY_ENGINE_SCRIPT=$Root\asset_engine\server.py" `
  --dart-define="ASSET_FOUNDRY_BLENDER=$Blender"
