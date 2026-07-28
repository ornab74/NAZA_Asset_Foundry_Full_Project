$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter is required on PATH.' }
if (-not (Get-Command py -ErrorAction SilentlyContinue)) { throw 'Python launcher py.exe is required.' }

$Temp = Join-Path $env:TEMP ("naza-foundry-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force $Temp | Out-Null
try {
  Copy-Item lib -Destination $Temp -Recurse
  Copy-Item pubspec.yaml, analysis_options.yaml -Destination $Temp
  flutter create --no-pub --project-name naza_asset_foundry --org com.naza --platforms android,linux,windows,macos,ios,web .
  Remove-Item lib -Recurse -Force
  Copy-Item (Join-Path $Temp 'lib') -Destination . -Recurse
  Copy-Item (Join-Path $Temp 'pubspec.yaml') -Destination . -Force
  Copy-Item (Join-Path $Temp 'analysis_options.yaml') -Destination . -Force
} finally {
  Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue
}

flutter pub get
py -3.12 -m venv .asset-foundry-venv
$Python = Join-Path $Root '.asset-foundry-venv\Scripts\python.exe'
& $Python -m pip install --upgrade pip
& $Python -m pip install -r asset_engine\requirements.txt
& $Python -m unittest asset_engine.test_policy -v
& $Python tool\check_project.py
Write-Host 'NAZA Asset Foundry is ready. Run scripts\run_asset_foundry.ps1'
