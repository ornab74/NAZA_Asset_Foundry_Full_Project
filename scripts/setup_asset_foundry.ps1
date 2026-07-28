$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Venv = if ($env:ASSET_FOUNDRY_VENV) { $env:ASSET_FOUNDRY_VENV } else { Join-Path $Root ".asset-foundry-venv" }
$Python = if ($env:PYTHON) { $env:PYTHON } else { "py" }

if ($Python -eq "py") {
  & py -3.12 -m venv $Venv
} else {
  & $Python -m venv $Venv
}

$VenvPython = Join-Path $Venv "Scripts\python.exe"
& $VenvPython -m pip install --upgrade pip
& $VenvPython -m pip install -r (Join-Path $Root "asset_engine\requirements.txt")

Write-Host "Asset Foundry Python environment is ready: $Venv"
Write-Host "Set the Python executable in Settings to: $VenvPython"
Write-Host "Install Blender separately and add blender.exe to PATH."
Write-Host "Run: flutter run -t lib/asset_foundry_main.dart"
