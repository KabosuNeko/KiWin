#Requires -Version 5.1
<#
KiWin: debloat Windows 11. One script, no installer.

    irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/KiWin.ps1 | iex

Flags (run the file or a scriptblock instead of plain iex):
    powershell -ExecutionPolicy Bypass -File .\KiWin.ps1 -Browser Firefox -Yes
    & ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/KabosuNeko/KiWin/main/KiWin.ps1'))) -DryRun

Remove the Windows Update policy that KiWin versions before this one set:
    irm https://raw.githubusercontent.com/KabosuNeko/KiWin/main/Assets/debloat_scripts/undo_update_policy.ps1 | iex
#>
[CmdletBinding()]
param(
    [ValidateSet('None', 'Waterfox', 'Helium', 'Firefox', 'Brave', 'LibreWolf')]
    [string]$Browser = 'None',

    [string[]]$Skip = @(),

    [switch]$Latest,
    [switch]$DryRun,
    [switch]$Yes,

    # Accepted so old command lines keep working; every run now downloads fresh copies.
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Add TLS 1.2 without turning off TLS 1.3 where the OS already offers it.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$RawBase = 'https://raw.githubusercontent.com/KabosuNeko/KiWin/main'
$work = Join-Path $env:LOCALAPPDATA 'KiWinScript'
$ext = Join-Path $work 'external_scripts'
$logDir = Join-Path $env:LOCALAPPDATA 'KiWin\Logs'
$winutilConfig = Join-Path $work 'winutil-config.json'

# shortcut: tested releases pinned by hand, bump version and hash when upstream fixes something we need (-Latest skips the pin).
$pinned = @{
    WinUtil            = '26.10.28'
    WinUtilSha256      = 'D0444CB266953D927E5CEE71455F4F1A6DA2D5B3CFD7E440DCEB4E6B1CBF4F7F'
    Win11Debloat       = '2026.10.30'
    Win11DebloatSha256 = '6830BF501D2740C3317133AC0ECDC2A3AB80ED7F6C83E7F0F20DC66AFBF758A7'
}

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

# Only what Win11Debloat does not already cover, so each change has one owner.
$winutilTweaks = @(
    'WPFTweaksActivity', 'WPFTweaksConsumerFeatures', 'WPFTweaksDisableBGapps',
    'WPFTweaksTelemetry', 'WPFTweaksWPBT', 'WPFTweaksServices',
    'WPFTweaksRemoveOneDrive', 'WPFTweaksRemoveHomeAndGallery', 'WPFTweaksWindowsAI',
    'WPFTweaksReservedStorage'
)

$debloatArgs = @(
    '-Silent', '-RemoveApps', '-RemoveGamingApps', '-DisableTelemetry', '-DisableBing',
    '-DisableSuggestions', '-DisableLockscreenTips', '-RevertContextMenu',
    '-DisableWidgets', '-DisableCopilot', '-ClearStartAllUsers', '-DisableDVR',
    '-DisableStartRecommended', '-ExplorerToThisPC',
    '-DisableDesktopSpotlight', '-DisableSettings365Ads', '-DisableSettingsHome', '-DisablePaintAI',
    '-DisableNotepadAI', '-DisableEdgeAI', '-DisableStickyKeys', '-DisableEdgeAds',
    '-DisableBraveBloat', '-DisableRecall', '-DisableAISvcAutoStart', '-DisableClickToDo',
    '-DisableDeliveryOptimization',
    '-DisableDeviceAutoAppDownload', '-DisableStoreSearchSuggestions',
    '-DisableLocationServices', '-DisableFindMyDevice', '-PreventUpdateAutoReboot',
    '-DisableStartPhoneLink', '-DisableModernStandbyNetworking'
)

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Runs a script in a child Windows PowerShell and returns its exit code.
# Throws when the code is not in -OkCodes or the step outlives -TimeoutMinutes.
function Invoke-ChildScript {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Arguments = @(),
        [int]$TimeoutMinutes = 10,
        [int[]]$OkCodes = @(0)
    )

    $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Path) + $Arguments
    $argLine = ($all | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '

    $proc = Start-Process powershell.exe -ArgumentList $argLine -NoNewWindow -PassThru
    $null = $proc.Handle  # without a cached handle, ExitCode is empty once the process is gone
    if (-not $proc.WaitForExit($TimeoutMinutes * 60000)) {
        & taskkill.exe /PID $proc.Id /T /F | Out-Null
        throw "$(Split-Path $Path -Leaf) did not finish within $TimeoutMinutes minutes and was stopped."
    }
    $proc.WaitForExit()
    if ($OkCodes -notcontains $proc.ExitCode) {
        throw "$(Split-Path $Path -Leaf) exited with code $($proc.ExitCode)"
    }
    return $proc.ExitCode
}

# A brand-new account often has App Installer unregistered, so winget is missing.
function Initialize-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop
    }
    catch { }
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
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

    # Running through irm | iex: no repo on disk. Always fetch fresh copies, so
    # fixes to the helpers reach people who ran an older KiWin before.
    $dir = Join-Path $work 'scripts'
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    foreach ($name in 'create_restore_point.ps1', 'edge_vanisher.ps1', 'unpin_taskbar_start.ps1', 'start2_blank.bin',
                      'undo_update_policy.ps1') {
        Invoke-WebRequest "$RawBase/Assets/debloat_scripts/$name" -OutFile (Join-Path $dir $name) -UseBasicParsing
    }
    return $dir
}

function Save-VerifiedFile {
    param([string]$Uri, [string]$OutFile, [string]$Sha256)
    Invoke-WebRequest $Uri -OutFile $OutFile -UseBasicParsing
    if ($Sha256) {
        $actual = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash
        if ($actual -ne $Sha256.ToUpperInvariant()) {
            Remove-Item -LiteralPath $OutFile -Force
            throw "Checksum mismatch for $Uri (expected $Sha256, got $actual)."
        }
    }
}

function Get-UpstreamScripts {
    if ($Latest) {
        $wuTag = (Invoke-RestMethod 'https://api.github.com/repos/ChrisTitusTech/winutil/releases/latest').tag_name
        $wdTag = (Invoke-RestMethod 'https://api.github.com/repos/Raphire/Win11Debloat/releases/latest').tag_name
        $wuHash = $null
        Write-Warning "-Latest: WinUtil $wuTag is used without a checksum."
    }
    else {
        $wuTag = $pinned.WinUtil
        $wdTag = $pinned.Win11Debloat
        $wuHash = $pinned.WinUtilSha256
        $wdHash = $pinned.Win11DebloatSha256
    }

    Write-Host "    downloading WinUtil $wuTag and Win11Debloat $wdTag"
    Remove-Item -LiteralPath $ext -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $ext | Out-Null

    $wdBase = "https://github.com/Raphire/Win11Debloat/releases/download/$wdTag"
    if ($Latest) {
        $sums = Join-Path $ext 'SHA256SUMS'
        Invoke-WebRequest "$wdBase/SHA256SUMS" -OutFile $sums -UseBasicParsing
        $line = Get-Content -LiteralPath $sums | Where-Object { $_ -match '^([0-9a-fA-F]{64})\s+\*?Win11Debloat\.zip\s*$' } | Select-Object -First 1
        if (-not $line) { throw "Win11Debloat $wdTag has no checksum for Win11Debloat.zip." }
        $wdHash = ($line -split '\s+')[0]
    }

    $winutil = Join-Path $ext 'winutil.ps1'
    Save-VerifiedFile "https://github.com/ChrisTitusTech/winutil/releases/download/$wuTag/winutil.ps1" $winutil $wuHash
    $zip = Join-Path $ext 'Win11Debloat.zip'
    Save-VerifiedFile "$wdBase/Win11Debloat.zip" $zip $wdHash
    Expand-Archive -LiteralPath $zip -DestinationPath $ext -Force
    Remove-Item -LiteralPath $zip -Force

    $dir = Get-ChildItem $ext -Directory -Filter 'Win11Debloat*' | Select-Object -First 1
    if (-not $dir) { throw 'The Win11Debloat archive did not contain the expected folder.' }
    $script = Join-Path $dir.FullName 'Win11Debloat.ps1'
    if (-not (Test-Path $script)) { throw 'Win11Debloat.ps1 was not found in the downloaded release.' }
    if (-not (Select-String -LiteralPath $winutil -Pattern '\[string\]\s*\$Config' -Quiet)) {
        throw 'This WinUtil release no longer accepts -Config.'
    }
    return @{ WinUtil = $winutil; Win11Debloat = $script; WinUtilVersion = $wuTag; Win11DebloatVersion = $wdTag }
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

# WinUtil's "Apply Recommended" Windows Update button is not reachable through -Config,
# so its function is copied out of the verified WinUtil file into a script of its own.
function New-WinUtilUpdatesScript([string]$WinUtilPath, [string]$OutFile) {
    $ast = [Management.Automation.Language.Parser]::ParseFile($WinUtilPath, [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-WPFUpdatessecurity' }, $true)
    if (-not $fn) { return $false }
    # Write-WinUtilLog belongs to WinUtil's window; the function's Write-Host lines already show progress.
    [IO.File]::WriteAllText($OutFile, "function Write-WinUtilLog { }`n$($fn.Extent.Text)`nInvoke-WPFUpdatessecurity`n", [Text.UTF8Encoding]::new($false))
    return $true
}

# Signed-in OneDrive: removing it would leave cloud-only files unreachable on this PC.
function Test-OneDriveInUse {
    $accounts = Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue
    foreach ($account in $accounts) {
        if ((Get-ItemProperty -LiteralPath $account.PSPath -ErrorAction SilentlyContinue).UserEmail) { return $true }
    }
    return $false
}

if (-not $DryRun -and -not (Test-Admin)) {
    $forward = @()
    if ($Browser -ne 'None') { $forward += "-Browser $Browser" }
    if ($skipList.Count -gt 0) { $forward += "-Skip $($skipList -join ',')" }
    if ($Latest) { $forward += '-Latest' }
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

$browserId = if ($Browser -eq 'None') { '' } else { $browserPackages[$Browser] }

$doRestore = $skipList -notcontains 'restore-point'
$doBrowser = [bool]$browserId -and $skipList -notcontains 'browser'
# Removing Edge without installing a replacement would leave the machine with no browser.
$doEdge = $doBrowser -and $skipList -notcontains 'edge'
$doDebloat = $skipList -notcontains 'win11debloat'
$doUnpin = $skipList -notcontains 'unpin'

$notes = @()
if (-not $doEdge -and $skipList -notcontains 'edge') {
    $notes += 'Microsoft Edge is kept: no replacement browser is being installed (pass -Browser to remove it).'
}

$supported = Get-SupportedSwitches $paths.Win11Debloat ($debloatArgs + '-Sysprep')
$debloatFlags = @($supported | Where-Object { $_ -ne '-Sysprep' })
$dropped = @($debloatArgs | Where-Object { $debloatFlags -notcontains $_ })
if ($dropped.Count -gt 0) { Write-Warning "Win11Debloat no longer supports: $($dropped -join ', ')" }
if ($debloatFlags -notcontains '-Silent') { throw 'Win11Debloat dropped -Silent; refusing to run it interactively.' }
$debloatLogArgs = if ((Get-Content -LiteralPath $paths.Win11Debloat -Raw) -match '\[string\]\s*\$LogPath\b') { @('-LogPath', $logDir) } else { @() }
$doSysprep = $doDebloat -and ($skipList -notcontains 'new-users') -and ($supported -contains '-Sysprep')

$tweakNames = @($winutilTweaks)
if (Test-OneDriveInUse) {
    $tweakNames = @($tweakNames | Where-Object { $_ -ne 'WPFTweaksRemoveOneDrive' })
    $notes += 'OneDrive is kept: an account is signed in, and removing it would cut off cloud-only files.'
}
$tweaks = @(Get-SupportedTweaks $paths.WinUtil $tweakNames)
$droppedTweaks = @($tweakNames | Where-Object { $tweaks -notcontains $_ })
if ($droppedTweaks.Count -gt 0) { Write-Warning "WinUtil no longer has: $($droppedTweaks -join ', ')" }
$doWinUtil = $skipList -notcontains 'winutil' -and $tweaks.Count -gt 0

$updatesScript = Join-Path $work 'winutil-updates.ps1'
$doUpdates = $skipList -notcontains 'updates' -and (New-WinUtilUpdatesScript $paths.WinUtil $updatesScript)
if ($skipList -notcontains 'updates' -and -not $doUpdates) {
    Write-Warning "WinUtil $($paths.WinUtilVersion) has no Invoke-WPFUpdatessecurity; Windows Update settings are skipped."
}
if ($doUpdates -and $cv.EditionID -match '^Core') {
    $notes += 'WinUtil lists its update settings for Pro, Enterprise and Education; on Home the deferrals may be ignored.'
}

# Win11Debloat already clears Start for every user, so only the taskbar is left here.
$unpinArgs = if ($doDebloat -and $debloatFlags -contains '-ClearStartAllUsers') { @('-TaskbarOnly') } else { @() }

# Older KiWin versions applied WinUtil's Razer block, which also stops driver downloads.
$driverSearch = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -ErrorAction SilentlyContinue
if ($driverSearch -and $driverSearch.SearchOrderConfig -eq 0) {
    $notes += "Automatic driver downloads are off (left by an older KiWin). To turn them back on:`n    irm $RawBase/Assets/debloat_scripts/undo_razer_block.ps1 | iex"
}

# Older KiWin versions installed their own update policy, with a task that re-applies it.
# Same test as undo_update_policy.ps1, which removes it before WinUtil's settings go on.
$oldPolicy = (Test-Path 'C:\ProgramData\KiWin\UpdatePolicy\LastApplied.txt') -or [bool](Get-ScheduledTask -ErrorAction SilentlyContinue `
    -TaskName 'KiWinUpdatePolicyRenewal', 'WindowsUpdateSettingsTask', 'CheckSecuritySettings', 'ReapplySecuritySettings')
if ($oldPolicy -and -not $doUpdates) {
    $notes += "An older KiWin set a Windows Update policy that blocks drivers and .NET/Office updates. To remove it:`n    irm $RawBase/Assets/debloat_scripts/undo_update_policy.ps1 | iex"
}

$steps = @()
if ($doRestore) { $steps += 'System Restore point (you are asked before continuing if it fails)' }
if ($doBrowser) { $steps += "Install $Browser ($browserId)" }
if ($doEdge) { $steps += 'Remove Microsoft Edge (your Edge profile data is kept)' }
if ($doWinUtil) { $steps += "WinUtil tweaks ($($tweaks.Count)): $($tweaks -replace '^WPFTweaks' -join ', ')" }
if ($doUpdates) {
    if ($oldPolicy) { $steps += 'Remove the Windows Update policy and task an older KiWin installed' }
    $steps += 'Windows Update, WinUtil "Apply Recommended": feature updates 365 days late, quality updates 4 days late, no drivers from Windows Update, ask before installing'
}
if ($doDebloat) { $steps += "Win11Debloat ($($debloatFlags.Count) flags)$(if ($doSysprep) { ' + sysprep pass' } else { '' })" }
if ($doUnpin) { $steps += $(if ($unpinArgs) { 'Unpin taskbar' } else { 'Unpin taskbar and Start' }) }

Write-Host "Windows: $osName (build $($cv.CurrentBuildNumber))"
Write-Host "WinUtil $($paths.WinUtilVersion): $($paths.WinUtil)"
Write-Host "Win11Debloat $($paths.Win11DebloatVersion): $($paths.Win11Debloat)"
Write-Host 'Steps:'
$steps | ForEach-Object { Write-Host "  - $_" }
$notes | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }

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

# After YES: registering App Installer is already a change to the system.
if ($doBrowser -and -not (Initialize-Winget)) {
    throw 'winget is required to install the browser. Install App Installer from the Store, or use -Skip browser.'
}

[IO.File]::WriteAllText($winutilConfig, (ConvertTo-Json @($tweaks) -Compress), [Text.UTF8Encoding]::new($false))

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir ('KiWin-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $logFile | Out-Null
$failed = $false
try {
    if ($doRestore) {
        Write-Host '==> System Restore point'
        try {
            $code = Invoke-ChildScript (Join-Path $scripts 'create_restore_point.ps1') -OkCodes 0, 2
        }
        catch {
            Write-Warning $_.Exception.Message
            $code = 2
        }
        if ($code -ne 0) {
            if ($Yes) {
                Write-Warning 'Continuing without a restore point because -Yes was given.'
            }
            elseif ((Read-Host 'No restore point was created. Type YES to continue without one') -ne 'YES') {
                Write-Host 'Aborted. Nothing else was changed.'
                return
            }
        }
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
        $null = Invoke-ChildScript (Join-Path $scripts 'edge_vanisher.ps1')
    }

    if ($doWinUtil) {
        Write-Host '==> WinUtil tweaks'
        $null = Invoke-ChildScript $paths.WinUtil @('-Config', $winutilConfig) -TimeoutMinutes 25
    }

    # Before Win11Debloat, whose -PreventUpdateAutoReboot WinUtil's function would otherwise remove.
    if ($doUpdates) {
        if ($oldPolicy) {
            Write-Host '==> Remove the older KiWin update policy'
            $null = Invoke-ChildScript (Join-Path $scripts 'undo_update_policy.ps1')
        }
        Write-Host '==> Windows Update (WinUtil Apply Recommended)'
        $null = Invoke-ChildScript $updatesScript
    }

    if ($doDebloat) {
        Write-Host '==> Win11Debloat'
        $null = Invoke-ChildScript $paths.Win11Debloat ($debloatFlags + $debloatLogArgs) -TimeoutMinutes 20
        if ($doSysprep) {
            Write-Host '==> Win11Debloat (Default profile, new user accounts)'
            try {
                $null = Invoke-ChildScript $paths.Win11Debloat ($debloatFlags + $debloatLogArgs + '-Sysprep') -TimeoutMinutes 20
            }
            catch {
                Write-Warning "Sysprep pass failed: $($_.Exception.Message) (the current user is already debloated)."
            }
        }
    }

    if ($doUnpin) {
        Write-Host '==> Unpin taskbar and Start'
        $null = Invoke-ChildScript (Join-Path $scripts 'unpin_taskbar_start.ps1') $unpinArgs
    }
}
catch {
    Write-Host "KiWin failed: $($_.Exception.Message)" -ForegroundColor Red
    $failed = $true
}
finally {
    Stop-Transcript | Out-Null
}

Write-Host "Log: $logFile"
if ($failed) {
    # exit inside iex or -Command closes the window before the error can be read.
    if ($PSCommandPath) { exit 1 }
    $global:LASTEXITCODE = 1
    return
}

Write-Host ''
Write-Host 'Done. Sign out or restart to finish applying the changes.' -ForegroundColor Green
