param(
    [string]$OutputDir = "dist",
    [string]$Win11DebloatTag = "2026.07.11"
)

$ErrorActionPreference = "Stop"
$ROOT = $PSScriptRoot
$SCRIPT_BUNDLE_DIR = Join-Path $ROOT "external_scripts"

$outDir = Join-Path $ROOT $OutputDir
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }

$winutilPath = Join-Path $SCRIPT_BUNDLE_DIR "winutil.ps1"
$win11debloatDirs = @()
if (Test-Path $SCRIPT_BUNDLE_DIR) {
    $win11debloatDirs = Get-ChildItem $SCRIPT_BUNDLE_DIR -Directory -Filter "Raphire-Win11Debloat-*" -ErrorAction SilentlyContinue
}

if ((Test-Path $winutilPath) -and ($win11debloatDirs.Count -gt 0)) {
    Write-Host "External debloat scripts already present; skipping download."
    $win11debloatRoot = $win11debloatDirs[0].FullName
}
else {
    if (-not (Test-Path $SCRIPT_BUNDLE_DIR)) { New-Item -ItemType Directory -Force -Path $SCRIPT_BUNDLE_DIR | Out-Null }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $u1 = "https://christitus.com/win"
    $u2 = "https://api.github.com/repos/Raphire/Win11Debloat/zipball/$Win11DebloatTag"
    $o1 = $winutilPath
    $zip2 = Join-Path $SCRIPT_BUNDLE_DIR "win11debloat.zip"

    Write-Host "Downloading WinUtil..."
    Invoke-WebRequest -Uri $u1 -OutFile $o1 -UseBasicParsing
    Write-Host "Downloading Win11Debloat ($Win11DebloatTag)..."
    Invoke-WebRequest -Uri $u2 -OutFile $zip2 -UseBasicParsing
    Expand-Archive -LiteralPath $zip2 -DestinationPath $SCRIPT_BUNDLE_DIR -Force
    Remove-Item -LiteralPath $zip2 -Force

    Write-Host "Patching WinUtil..."
    $c = Get-Content -LiteralPath $o1 -Raw -Encoding UTF8
    $patched = [regex]::Replace(
        $c,
        '(?ms)^\s*Write-Host ""Installing features\.\.\.""\s*.*?Write-Host ""Done\.""',
        'Write-Host ""Features installation skipped""' + [Environment]::NewLine)
    Set-Content -LiteralPath $o1 -Value $patched -Encoding UTF8
}

Write-Host "Publishing KiWin..."
dotnet publish (Join-Path $ROOT "src\KiWin.App\KiWin.App.csproj") `
    -c Release `
    -r win-x64 `
    --self-contained `
    -p:PublishSingleFile=true `
    -p:PublishReadyToRun=false `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:IncludeAllContentForSelfExtract=false `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $outDir

Write-Host ""
Write-Host "Build complete: $outDir\KiWin.exe"
Write-Host "Assets (media, locales, presets, debloat_scripts, external_scripts) are copied next to KiWin.exe."

Copy-Item (Join-Path $ROOT "Assets\media\ICON.ico") (Join-Path $outDir "media\ICON.ico") -Force
Write-Host "ICON.ico re-copied to dist\media."

Write-Host ""
Write-Host "Packaging release bundle..."
$zipPath = Join-Path $ROOT "KiWin.zip"
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zipPath -CompressionLevel Optimal -Force
Write-Host "Release bundle: $zipPath"
