# KiWin one-liner installer
#
# Usage:
#   irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/kiwin-install.ps1 | iex
#
# Downloads the latest KiWin release bundle from GitHub Releases, extracts it to
# %LOCALAPPDATA%\KiWin and launches the app. KiWin will show the UAC prompt and
# handle elevation itself.

$ErrorActionPreference = "Stop"

$ZipUrl = "https://github.com/KabosuNeko/KiWin/releases/latest/download/KiWin.zip"
$Dest   = Join-Path $env:LOCALAPPDATA "KiWin"
$Zip    = Join-Path $env:TEMP "KiWin.zip"

Write-Host "KiWin installer"
Write-Host "  Downloading: $ZipUrl" -ForegroundColor Cyan

Invoke-WebRequest -Uri $ZipUrl -OutFile $Zip -UseBasicParsing

Write-Host "  Extracting to: $Dest" -ForegroundColor Cyan
if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Force -Path $Dest | Out-Null }
Expand-Archive -LiteralPath $Zip -DestinationPath $Dest -Force

$exe = Join-Path $Dest "KiWin.exe"
if (-not (Test-Path $exe)) {
    throw "KiWin.exe not found after extraction: $exe"
}

Remove-Item $Zip -Force -ErrorAction SilentlyContinue

Write-Host "  Launching KiWin... (accept the UAC prompt)" -ForegroundColor Cyan
Start-Process -FilePath $exe
