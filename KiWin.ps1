#Requires -Version 5.1
<#
KiWin: debloat Windows 11. One script, no installer.

    irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/KiWin.ps1 | iex

Flags (run the file or a scriptblock instead of plain iex):
    powershell -ExecutionPolicy Bypass -File .\KiWin.ps1 -Browser Firefox -Yes
    & ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/KabosuNeko/KiWin/main/KiWin.ps1'))) -DryRun

Undo the update policy later:
    irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/Assets/debloat_scripts/undo_update_policy.ps1 | iex
#>
[CmdletBinding()]
param(
    [ValidateSet('None', 'Waterfox', 'Helium', 'Firefox', 'Brave', 'LibreWolf')]
    [string]$Browser = 'None',

    [string[]]$Skip = @(),

    [switch]$Refresh,
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RawBase = 'https://raw.githubusercontent.com/KabosuNeko/KiWin/main'
$work = Join-Path $env:LOCALAPPDATA 'KiWinScript'
$ext = Join-Path $work 'external_scripts'
$winutilConfig = Join-Path $work 'winutil-config.json'

# Accept "-Skip edge,winutil" both as an array and as one argument from `powershell -File`.
$skipList = @($Skip | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
$validSkips = @('restore-point', 'edge', 'browser', 'winutil', 'win11debloat', 'updates', 'unpin', 'new-users')
$unknownSkips = @($skipList | Where-Object { $validSkips -notcontains $_ })
if ($unknownSkips.Count -gt 0) {
    throw "Unknown -Skip value(s): $($unknownSkips -join ', '). Valid values: $($validSkips -join ', ')."
}

$browserPackages = @{
    Waterfox  = 'Waterfox.Waterfox'
    Helium    = 'ImputNet.Helium'
    Firefox   = 'Mozilla.Firefox'
    Brave     = 'Brave.Brave'
    LibreWolf = 'LibreWolf.LibreWolf'
}

$winutilTweaks = @(
    'WPFTweaksActivity', 'WPFTweaksConsumerFeatures', 'WPFTweaksDisableBGapps',
    'WPFTweaksTelemetry', 'WPFTweaksWPBT', 'WPFTweaksWidget', 'WPFTweaksServices',
    'WPFTweaksDisplay', 'WPFTweaksRightClickMenu', 'WPFTweaksRemoveOneDrive',
    'WPFTweaksRemoveHomeAndGallery', 'WPFTweaksWindowsAI', 'WPFTweaksDisableStoreSearch',
    'WPFTweaksLocation', 'WPFTweaksReservedStorage'
)

$debloatArgs = @(
    '-Silent', '-RemoveApps', '-RemoveGamingApps', '-DisableTelemetry', '-DisableBing',
    '-DisableSuggestions', '-DisableLockscreenTips', '-RevertContextMenu',
    '-DisableWidgets', '-DisableCopilot', '-ClearStartAllUsers', '-DisableDVR',
    '-DisableStartRecommended', '-ExplorerToThisPC',
    '-DisableDesktopSpotlight', '-DisableSettings365Ads', '-DisableSettingsHome', '-DisablePaintAI',
    '-DisableNotepadAI', '-DisableEdgeAI', '-DisableStickyKeys', '-DisableEdgeAds',
    '-DisableBraveBloat', '-DisableRecall', '-DisableAISvcAutoStart', '-DisableClickToDo',
    '-DisableSnapLayouts', '-DisableDeliveryOptimization',
    '-DisableDeviceAutoAppDownload', '-DisableStoreSearchSuggestions',
    '-DisableLocationServices', '-DisableFindMyDevice', '-PreventUpdateAutoReboot',
    '-DisableStartPhoneLink', '-DisableModernStandbyNetworking'
)

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ChildScript {
    param([Parameter(Mandatory)][string]$Path, [string[]]$Arguments = @())

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$(Split-Path $Path -Leaf) exited with code $LASTEXITCODE"
    }
}

function Install-WingetPackage {
    param([Parameter(Mandatory)][string]$Id)

    # No stderr redirect: with $ErrorActionPreference = 'Stop', PowerShell 5.1 turns redirected native stderr into a terminating error.
    $listed = (& winget list -e --id $Id --source winget --accept-source-agreements | Out-String)
    if ($LASTEXITCODE -eq 0 -and $listed -match [regex]::Escape($Id)) {
        Write-Host "    $Id is already installed"
        return
    }
    & winget install -e --silent --source winget --id $Id --accept-package-agreements --accept-source-agreements
    # 0x8A150061: already installed, no applicable upgrade.
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335135) {
        throw "winget install $Id exited with code $LASTEXITCODE"
    }
}

function Get-KiWinScripts {
    $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Assets\debloat_scripts' } else { '' }
    if ($local -and (Test-Path $local)) { return $local }

    # Running through irm | iex: no repo on disk, so fetch the helper scripts once.
    $dir = Join-Path $work 'scripts'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    foreach ($name in 'create_restore_point.ps1', 'edge_vanisher.ps1', 'update_policy_changer.ps1',
                      'unpin_taskbar_start.ps1', 'start2_blank.bin') {
        $target = Join-Path $dir $name
        if ($Refresh -or -not (Test-Path $target)) {
            Invoke-WebRequest "$RawBase/Assets/debloat_scripts/$name" -OutFile $target -UseBasicParsing
        }
    }
    return $dir
}

function Get-UpstreamScripts {
    $winutil = Join-Path $ext 'winutil.ps1'
    $cached = Get-ChildItem $ext -Directory -Filter 'Raphire-Win11Debloat-*' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $Refresh -and (Test-Path $winutil) -and $cached) {
        $cachedScript = Join-Path $cached.FullName 'Win11Debloat.ps1'
        if (Test-Path $cachedScript) {
            return @{ WinUtil = $winutil; Win11Debloat = $cachedScript }
        }
    }

    Write-Host '    downloading WinUtil and the latest Win11Debloat release'
    Remove-Item $ext -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $ext | Out-Null

    Invoke-WebRequest 'https://christitus.com/win' -OutFile $winutil -UseBasicParsing
    $tag = (Invoke-RestMethod 'https://api.github.com/repos/Raphire/Win11Debloat/releases/latest').tag_name
    $zip = Join-Path $ext 'win11debloat.zip'
    Invoke-WebRequest "https://api.github.com/repos/Raphire/Win11Debloat/zipball/$tag" -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $ext -Force
    Remove-Item -LiteralPath $zip -Force

    $dir = Get-ChildItem $ext -Directory -Filter 'Raphire-Win11Debloat-*' | Select-Object -First 1
    if (-not $dir) { throw 'The Win11Debloat archive did not contain the expected folder.' }
    $script = Join-Path $dir.FullName 'Win11Debloat.ps1'
    if (-not (Test-Path $script)) { throw 'Win11Debloat.ps1 was not found in the downloaded release.' }
    if (-not (Select-String -LiteralPath $winutil -Pattern '\[string\]\s*\$Config' -Quiet)) {
        throw 'WinUtil is missing or no longer accepts -Config; rerun with -Refresh.'
    }
    return @{ WinUtil = $winutil; Win11Debloat = $script }
}

# Upstream drops flags and tweaks between releases; keep only what this build supports.
function Get-SupportedSwitches {
    param([string]$Path, [string[]]$Names)
    $declared = [regex]::Matches((Get-Content -LiteralPath $Path -Raw), '\[switch\]\s*\$(\w+)') |
        ForEach-Object { '-' + $_.Groups[1].Value }
    $Names | Where-Object { $declared -contains $_ }
}

function Get-SupportedTweaks {
    param([string]$Path, [string[]]$Names)
    $text = Get-Content -LiteralPath $Path -Raw
    $Names | Where-Object { $text -match ('"' + [regex]::Escape($_) + '"\s*:') }
}

if (-not $DryRun -and -not (Test-Admin)) {
    $forward = @()
    if ($Browser -ne 'None') { $forward += "-Browser $Browser" }
    if ($skipList.Count -gt 0) { $forward += "-Skip $($skipList -join ',')" }
    if ($Refresh) { $forward += '-Refresh' }
    if ($Yes) { $forward += '-Yes' }

    if ($PSCommandPath) {
        $argLine = '-NoExit -NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $PSCommandPath, ($forward -join ' ')
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argLine
    }
    else {
        $iex = "& ([scriptblock]::Create((irm '$RawBase/KiWin.ps1'))) $($forward -join ' ')"
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"$iex`""
    }
    return
}

$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
if ([int]$cv.CurrentBuildNumber -lt 22000) {
    throw "Windows 11 is required (detected $($cv.ProductName), build $($cv.CurrentBuildNumber))."
}
# 24H2+ still reports ProductName as "Windows 10 Pro"; the build number is authoritative.
$osName = $cv.ProductName -replace '^Windows 10', 'Windows 11'

if (-not $DryRun -and -not $Yes -and $skipList -notcontains 'browser' -and
    -not $PSBoundParameters.ContainsKey('Browser')) {
    Write-Host ''
    Write-Host 'Browsers: Waterfox, Helium, Firefox, Brave, LibreWolf'
    $choice = Read-Host 'Install a browser? [Enter = none]'
    while ($choice -and $browserPackages.Keys -notcontains $choice) {
        $choice = Read-Host 'Unknown browser. Waterfox, Helium, Firefox, Brave, LibreWolf, or Enter for none'
    }
    if ($choice) { $Browser = $browserPackages.Keys | Where-Object { $_ -eq $choice } | Select-Object -First 1 }
}

$scripts = Get-KiWinScripts
$paths = Get-UpstreamScripts

$supported = Get-SupportedSwitches $paths.Win11Debloat ($debloatArgs + '-Sysprep')
$debloatFlags = @($supported | Where-Object { $_ -ne '-Sysprep' })
$tweaks = @(Get-SupportedTweaks $paths.WinUtil $winutilTweaks)
$dropped = @($debloatArgs | Where-Object { $debloatFlags -notcontains $_ })
if ($dropped.Count -gt 0) { Write-Warning "Win11Debloat no longer supports: $($dropped -join ', ')" }
if ($debloatFlags -notcontains '-Silent') { throw 'Win11Debloat dropped -Silent; refusing to run it interactively.' }
$droppedTweaks = @($winutilTweaks | Where-Object { $tweaks -notcontains $_ })
if ($droppedTweaks.Count -gt 0) { Write-Warning "WinUtil no longer has: $($droppedTweaks -join ', ')" }

$browserId = if ($Browser -eq 'None') { '' } else { $browserPackages[$Browser] }

$doRestore = $skipList -notcontains 'restore-point'
$doBrowser = [bool]$browserId -and $skipList -notcontains 'browser'
# Removing Edge without installing a replacement would leave the machine with no browser.
$doEdge = $doBrowser -and $skipList -notcontains 'edge'
$edgeKeptNote = if (-not $doEdge -and $skipList -notcontains 'edge') {
    'Microsoft Edge is kept: no replacement browser is being installed (pass -Browser to remove it).'
}
$doWinUtil = $skipList -notcontains 'winutil' -and $tweaks.Count -gt 0
$doDebloat = $skipList -notcontains 'win11debloat'
$doSysprep = $doDebloat -and ($skipList -notcontains 'new-users') -and ($supported -contains '-Sysprep')
$doUpdates = $skipList -notcontains 'updates'
$doUnpin = $skipList -notcontains 'unpin'

if ($doBrowser -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget is required to install the browser. Install App Installer, or use -Skip browser.'
}

[IO.File]::WriteAllText($winutilConfig, (ConvertTo-Json $tweaks -Compress), [Text.UTF8Encoding]::new($false))

$steps = @()
if ($doRestore) { $steps += 'System Restore point' }
if ($doBrowser) { $steps += "Install $Browser ($browserId)" }
if ($doEdge) { $steps += 'Remove Microsoft Edge (your Edge profile data is kept)' }
if ($doWinUtil) { $steps += "WinUtil tweaks ($($tweaks.Count))" }
if ($doDebloat) { $steps += "Win11Debloat ($($debloatFlags.Count) flags)$(if ($doSysprep) { ' + sysprep pass' } else { '' })" }
if ($doUpdates) { $steps += 'Windows Update: stay on the current feature release, delay quality updates 4 days' }
if ($doUnpin) { $steps += 'Unpin taskbar and Start' }

Write-Host "Windows: $osName (build $($cv.CurrentBuildNumber))"
Write-Host "WinUtil: $($paths.WinUtil)"
Write-Host "Win11Debloat: $($paths.Win11Debloat)"
Write-Host 'Steps:'
$steps | ForEach-Object { Write-Host "  - $_" }
if ($edgeKeptNote) { Write-Host $edgeKeptNote -ForegroundColor Yellow }

if ($steps.Count -eq 0) {
    Write-Host 'Nothing to do: every step is skipped.'
    return
}

if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry run: nothing was changed.' -ForegroundColor Yellow
    return
}

if (-not $Yes) {
    Write-Host ''
    if ((Read-Host 'Type YES to apply these changes') -ne 'YES') {
        Write-Host 'Aborted.'
        return
    }
}

try {
    if ($doRestore) {
        Write-Host '==> System Restore point'
        # Best effort: the script reports the outcome and falls back to exporting the registry.
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'create_restore_point.ps1')
    }

    # The browser goes first: if it fails to install, the run stops before Edge is removed.
    if ($doBrowser) {
        Write-Host "==> Install $Browser"
        try {
            Install-WingetPackage 'Microsoft.VCRedist.2015+.x64'
        }
        catch {
            Write-Warning "VC++ redistributable install failed: $($_.Exception.Message)"
        }
        Install-WingetPackage $browserId
    }

    if ($doEdge) {
        Write-Host '==> Remove Microsoft Edge'
        Invoke-ChildScript (Join-Path $scripts 'edge_vanisher.ps1')
    }

    if ($doWinUtil) {
        Write-Host '==> WinUtil tweaks'
        Invoke-ChildScript $paths.WinUtil @('-Config', $winutilConfig)
    }

    if ($doDebloat) {
        Write-Host '==> Win11Debloat'
        Invoke-ChildScript $paths.Win11Debloat $debloatFlags
        if ($doSysprep) {
            Write-Host '==> Win11Debloat (Default profile, new user accounts)'
            try {
                Invoke-ChildScript $paths.Win11Debloat ($debloatFlags + '-Sysprep')
            }
            catch {
                Write-Warning "Sysprep pass failed: $($_.Exception.Message) (the current user is already debloated)."
            }
        }
    }

    if ($doUpdates) {
        Write-Host '==> Windows Update policy'
        Invoke-ChildScript (Join-Path $scripts 'update_policy_changer.ps1')
    }

    if ($doUnpin) {
        Write-Host '==> Unpin taskbar and Start'
        Invoke-ChildScript (Join-Path $scripts 'unpin_taskbar_start.ps1')
    }
}
catch {
    Write-Host "KiWin failed: $($_.Exception.Message)" -ForegroundColor Red
    # exit inside iex or -Command closes the window before the error can be read.
    if ($PSCommandPath) { exit 1 }
    $global:LASTEXITCODE = 1
    return
}

Write-Host ''
Write-Host 'Done. Sign out or restart to finish applying the changes.' -ForegroundColor Green
