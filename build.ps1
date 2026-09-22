param(
    [string]$OutputDir = "dist",
    [string]$Win11DebloatTag = "2026.08.24",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ROOT = $PSScriptRoot
$SCRIPT_BUNDLE_DIR = Join-Path $ROOT "external_scripts"
$versionsFile = Join-Path $SCRIPT_BUNDLE_DIR "versions.json"

$outDir = Join-Path $ROOT $OutputDir
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }

$winutilPath = Join-Path $SCRIPT_BUNDLE_DIR "winutil.ps1"
$win11debloatDirs = @()
if (Test-Path $SCRIPT_BUNDLE_DIR) {
    $win11debloatDirs = Get-ChildItem $SCRIPT_BUNDLE_DIR -Directory -Filter "Raphire-Win11Debloat-*" -ErrorAction SilentlyContinue
}

$needDownload = $Force -or -not (Test-Path $winutilPath) -or ($win11debloatDirs.Count -eq 0) -or -not (Test-Path $versionsFile)

if (-not $needDownload) {
    $versions = Get-Content -LiteralPath $versionsFile -Raw | ConvertFrom-Json
    Write-Host "External debloat scripts already present and verified; skipping download (-Force to refresh)."
    Write-Host ("  WinUtil sha256:      {0}" -f $versions.winutil.sha256)
    Write-Host ("  Win11Debloat tag:    {0}" -f $versions.win11debloat.tag)
    Write-Host ("  Win11Debloat sha256: {0}" -f $versions.win11debloat.sha256)
    $win11debloatRoot = $win11debloatDirs[0].FullName
}
else {
    if (Test-Path $SCRIPT_BUNDLE_DIR) { Remove-Item -Recurse -Force $SCRIPT_BUNDLE_DIR }
    New-Item -ItemType Directory -Force -Path $SCRIPT_BUNDLE_DIR | Out-Null

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

    Write-Host "Patching WinUtil (disable Windows feature installation)..."
    $c = Get-Content -LiteralPath $o1 -Raw -Encoding UTF8
    $featureGuard = 'if\s*\(\s*\$sync\.selectedFeatures\.Count\s*-gt\s*0\s*\)\s*\{'
    $guardMatches = [regex]::Matches($c, $featureGuard).Count
    if ($guardMatches -ne 1) {
        throw "WinUtil patch target not found exactly once (found $guardMatches). Upstream WinUtil changed; update the patch in build.ps1 before shipping."
    }
    $patched = [regex]::Replace($c, $featureGuard, 'if ($false -and $sync.selectedFeatures.Count -gt 0) {')
    if ($patched -eq $c) {
        throw "WinUtil patch did not change the script; refusing to ship an unpatched WinUtil."
    }
    Set-Content -LiteralPath $o1 -Value $patched -Encoding UTF8
    Write-Host "WinUtil patched: Windows feature installation disabled."

    $win11debloatDirs = Get-ChildItem $SCRIPT_BUNDLE_DIR -Directory -Filter "Raphire-Win11Debloat-*"
    if ($win11debloatDirs.Count -eq 0) { throw "Win11Debloat archive did not contain the expected Raphire-Win11Debloat-* folder." }
    $win11debloatRoot = $win11debloatDirs[0].FullName
    $win11Script = Join-Path $win11debloatRoot "Win11Debloat.ps1"
    if (-not (Test-Path $win11Script)) { throw "Win11Debloat.ps1 not found in $win11debloatRoot" }

    $versions = [ordered]@{
        fetchedUtc   = (Get-Date).ToUniversalTime().ToString("o")
        winutil      = [ordered]@{ source = $u1; sha256 = (Get-FileHash -LiteralPath $o1 -Algorithm SHA256).Hash.ToLowerInvariant() }
        win11debloat = [ordered]@{ tag = $Win11DebloatTag; source = $u2; sha256 = (Get-FileHash -LiteralPath $win11Script -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    $versions | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $versionsFile -Encoding UTF8
    Write-Host "Recorded external script versions to external_scripts\versions.json"
    Write-Host ("  WinUtil sha256:      {0}" -f $versions.winutil.sha256)
    Write-Host ("  Win11Debloat sha256: {0}" -f $versions.win11debloat.sha256)
}

Write-Host "Bundling assets and external scripts into appbundle.zip..."
$bundleDir = Join-Path $ROOT "src\KiWin.App\Resources"
New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null
$bundlePath = Join-Path $bundleDir "appbundle.zip"
if (Test-Path $bundlePath) { Remove-Item -Force $bundlePath }
$stage = Join-Path $bundleDir "stage"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path (Join-Path $stage "external_scripts") | Out-Null
Copy-Item (Join-Path $ROOT "Assets\*") $stage -Recurse -Force
Copy-Item (Join-Path $SCRIPT_BUNDLE_DIR "*") (Join-Path $stage "external_scripts") -Recurse -Force
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $bundlePath -CompressionLevel Optimal -Force
Remove-Item -Recurse -Force $stage

Write-Host "Building KiWin (.NET Framework 4.8)..."
dotnet publish (Join-Path $ROOT "src\KiWin.App\KiWin.App.csproj") `
    -c Release `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $outDir

$configFile = Join-Path $outDir "KiWin.exe.config"
if (Test-Path $configFile) {
    Remove-Item -Force $configFile
    Write-Host "Removed KiWin.exe.config (single-file build; runs on the installed .NET Framework CLR)."
}

$exePath = Join-Path $outDir "KiWin.exe"
$pfx = $env:KIWIN_SIGN_PFX
$pfxPassword = $env:KIWIN_SIGN_PFX_PASSWORD
$thumb = $env:KIWIN_SIGN_THUMBPRINT

if ($pfx -or $thumb) {
    $signtool = (Get-Command signtool.exe -ErrorAction SilentlyContinue).Source
    if (-not $signtool) { throw "Signing was requested but signtool.exe was not found on PATH (install the Windows SDK)." }
    $timestamp = "http://timestamp.digicert.com"
    if ($pfx) {
        Write-Host "Signing $exePath with PFX..."
        $pfxPath = Join-Path $env:TEMP ("kiwin_sign_" + [Guid]::NewGuid().ToString("N") + ".pfx")
        [IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($pfx))
        try {
            & $signtool sign /f $pfxPath /p $pfxPassword /fd SHA256 /tr $timestamp /td SHA256 $exePath
            if ($LASTEXITCODE -ne 0) { throw "signtool failed with exit code $LASTEXITCODE" }
        }
        finally {
            Remove-Item -LiteralPath $pfxPath -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host "Signing $exePath with certificate $thumb ..."
        & $signtool sign /sha1 $thumb /fd SHA256 /tr $timestamp /td SHA256 $exePath
        if ($LASTEXITCODE -ne 0) { throw "signtool failed with exit code $LASTEXITCODE" }
    }
    Write-Host "Signed KiWin.exe."
}
else {
    Write-Warning "KiWin.exe is NOT code-signed. Set KIWIN_SIGN_PFX (+ KIWIN_SIGN_PFX_PASSWORD) or KIWIN_SIGN_THUMBPRINT to sign releases (removes SmartScreen friction)."
}

Write-Host ""
Write-Host "Build complete: $outDir\KiWin.exe (single self-contained exe; run it directly)"
