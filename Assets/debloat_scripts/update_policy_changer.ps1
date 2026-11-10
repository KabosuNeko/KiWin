# Keeps Windows on the installed feature release (no feature upgrades) and
# delays monthly cumulative updates by 4 days. Cumulative updates still
# install, so this is not "security only": they carry non-security fixes too.
# Drivers from Windows Update are left alone.
#
# The pin is only set while the installed release has more than 60 days of
# servicing left. A SYSTEM task re-checks at startup and weekly: close to end
# of servicing it drops the pin so Windows can move to a supported release,
# and after a feature update it pins the new one.
#
# Values that existed before KiWin are saved to Original.json, and
# undo_update_policy.ps1 puts them back. Original implementation; the deferral
# technique follows DTLegit's FullWinUpdate-Disabler.

param(
    [switch]$Renewal
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator rights required." -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = "Continue"

$TaskName      = "KiWinUpdatePolicyRenewal"
$StateFolder   = "C:\ProgramData\KiWin\UpdatePolicy"
$OriginalFile  = Join-Path $StateFolder "Original.json"
$LegacyStamp   = Join-Path $StateFolder "LastApplied.txt"
$UnpinMarginDays = 60

$WuPolicyPath  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$WuAutoPath    = "$WuPolicyPath\AU"
$WuUxPath      = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

# End of servicing per Windows 11 release: Home/Pro first, Enterprise/Education second.
# Releases not listed are newer than this table and treated as supported.
$EndOfServicing = @{
    "21H2" = @("2023-10-10", "2024-10-08")
    "22H2" = @("2024-10-08", "2025-10-14")
    "23H2" = @("2025-11-11", "2026-11-10")
    "24H2" = @("2026-10-13", "2027-10-12")
    "25H2" = @("2027-10-12", "2028-10-10")
}

# Every value this script may write; Original.json records their state before KiWin.
$ManagedValues = @(
    @{ Path = $WuPolicyPath; Name = "ProductVersion" },
    @{ Path = $WuPolicyPath; Name = "TargetReleaseVersion" },
    @{ Path = $WuPolicyPath; Name = "TargetReleaseVersionInfo" },
    @{ Path = $WuPolicyPath; Name = "DeferQualityUpdates" },
    @{ Path = $WuPolicyPath; Name = "DeferQualityUpdatesPeriodInDays" },
    @{ Path = $WuAutoPath;   Name = "AUPowerManagement" },
    @{ Path = $WuUxPath;     Name = "ActiveHoursStart" },
    @{ Path = $WuUxPath;     Name = "ActiveHoursEnd" },
    @{ Path = $WuUxPath;     Name = "AllowMUUpdateService" },
    @{ Path = $WuUxPath;     Name = "SmartActiveHoursState" },
    @{ Path = $WuUxPath;     Name = "UserChoiceActiveHoursStart" },
    @{ Path = $WuUxPath;     Name = "UserChoiceActiveHoursEnd" }
)

function Set-RegValueIfChanged {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    try {
        $existing = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        $current = if ($null -ne $existing) { $existing.$Name } else { $null }
        if ($null -ne $current -and "$current" -ceq "$Value") {
            return $false
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Host "Set $Name = $Value ($Type)"
        return $true
    }
    catch {
        Write-Host "Failed to set $Name : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Remove-RegValueIfPresent {
    param([string]$Path, [string]$Name)
    if (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $Path -Name $Name -Force
        Write-Host "Removed $Name"
        return $true
    }
    return $false
}

function Get-FeatureRelease {
    $p = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
    foreach ($value in $p.DisplayVersion, $p.ReleaseId) {
        if ($value -match "^\d{2}H\d$") { return [string]$value }
    }
}

# Returns $null when the release is unknown to the table (newer, so supported).
function Get-EndOfServicing {
    param([string]$Release)
    if (-not $EndOfServicing.ContainsKey($Release)) { return $null }
    $edition = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).EditionID
    $index = if ($edition -match "Enterprise|Education") { 1 } else { 0 }
    return [datetime]::ParseExact($EndOfServicing[$Release][$index], "yyyy-MM-dd", $null)
}

function Save-OriginalValues {
    if (Test-Path $OriginalFile) { return }
    # An install from an older KiWin has its own values in place already;
    # recording them as "original" would make undo restore KiWin's policy.
    if ((Test-Path $LegacyStamp) -or (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        Write-Host "Earlier KiWin install found; the pre-KiWin values are unknown, so undo will remove them."
        return
    }
    $snapshot = foreach ($v in $ManagedValues) {
        $key = Get-Item -LiteralPath $v.Path -ErrorAction SilentlyContinue
        $exists = $key -and ($key.GetValueNames() -contains $v.Name)
        [pscustomobject]@{
            Path   = $v.Path
            Name   = $v.Name
            Exists = [bool]$exists
            Value  = if ($exists) { $key.GetValue($v.Name) } else { $null }
            Kind   = if ($exists) { [string]$key.GetValueKind($v.Name) } else { $null }
        }
    }
    ConvertTo-Json @($snapshot) | Set-Content -LiteralPath $OriginalFile -Encoding UTF8
}

function Set-KiWinUpdatePolicy {
    $changed = $false

    $release = Get-FeatureRelease
    $eos = if ($release) { Get-EndOfServicing $release } else { $null }
    $pin = $false
    if (-not $release) {
        Write-Warning "Could not detect the feature release; feature updates are not pinned."
    }
    elseif ($eos -and (Get-Date) -ge $eos.AddDays(-$UnpinMarginDays)) {
        Write-Warning ("Windows 11 {0} reaches end of servicing on {1:yyyy-MM-dd}; it is not pinned so Windows can upgrade to a supported release." -f $release, $eos)
    }
    else {
        $pin = $true
    }

    if ($pin) {
        $product = if ([Environment]::OSVersion.Version.Build -ge 22000) { "Windows 11" } else { "Windows 10" }
        if (Set-RegValueIfChanged $WuPolicyPath "ProductVersion" $product "String") { $changed = $true }
        if (Set-RegValueIfChanged $WuPolicyPath "TargetReleaseVersion" 1) { $changed = $true }
        if (Set-RegValueIfChanged $WuPolicyPath "TargetReleaseVersionInfo" $release "String") { $changed = $true }
    }
    else {
        # Drop a stale pin instead of leaving the machine on an old release.
        foreach ($name in "ProductVersion", "TargetReleaseVersion", "TargetReleaseVersionInfo") {
            if (Remove-RegValueIfPresent $WuPolicyPath $name) { $changed = $true }
        }
    }

    if (Set-RegValueIfChanged $WuPolicyPath "DeferQualityUpdates" 1) { $changed = $true }
    if (Set-RegValueIfChanged $WuPolicyPath "DeferQualityUpdatesPeriodInDays" 4) { $changed = $true }
    # Older KiWin versions blocked drivers, which leaves fresh installs without them.
    $drivers = Get-ItemProperty -Path $WuPolicyPath -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue
    if ($null -ne $drivers -and $drivers.ExcludeWUDriversInQualityUpdate -eq 1) {
        Remove-ItemProperty -Path $WuPolicyPath -Name "ExcludeWUDriversInQualityUpdate" -Force
        Write-Host "Removed ExcludeWUDriversInQualityUpdate (drivers from Windows Update are allowed again)"
        $changed = $true
    }

    if (Set-RegValueIfChanged $WuAutoPath "AUPowerManagement" 0) { $changed = $true }

    if (Set-RegValueIfChanged $WuUxPath "ActiveHoursStart" 8) { $changed = $true }
    if (Set-RegValueIfChanged $WuUxPath "ActiveHoursEnd" 2) { $changed = $true }
    if (Set-RegValueIfChanged $WuUxPath "AllowMUUpdateService" 0) { $changed = $true }
    if (Set-RegValueIfChanged $WuUxPath "SmartActiveHoursState" 0) { $changed = $true }
    if (Set-RegValueIfChanged $WuUxPath "UserChoiceActiveHoursStart" 8) { $changed = $true }
    if (Set-RegValueIfChanged $WuUxPath "UserChoiceActiveHoursEnd" 2) { $changed = $true }

    if ($changed) { Write-Host "Update policy applied." }
    else { Write-Host "Update policy already up to date." }
}

if ($Renewal) {
    Set-KiWinUpdatePolicy
    exit 0
}

# The renewal task runs a script from here as SYSTEM. Standard users can create
# folders under ProgramData, so one created in advance would be theirs to edit:
# take ownership and replace the ACL with SYSTEM/Administrators full, Users read.
function Protect-StateFolder {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "$Path is a link, not a folder."
    }
    # /L acts on links themselves, so a planted junction inside cannot redirect the change.
    & icacls.exe $Path /setowner "*S-1-5-32-544" /T /C /L /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls /setowner failed on $Path (code $LASTEXITCODE)" }
    & icacls.exe $Path /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" /T /C /L /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls /grant failed on $Path (code $LASTEXITCODE)" }
}

# Secure the folder before anything (snapshot, script copy) is written into it.
try {
    Protect-StateFolder (Split-Path $StateFolder -Parent)
    Protect-StateFolder $StateFolder
}
catch {
    Write-Host "Could not secure ${StateFolder}: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Save-OriginalValues
Set-KiWinUpdatePolicy
Remove-Item -LiteralPath $LegacyStamp -Force -ErrorAction SilentlyContinue

# The task runs a stable copy so it survives cleanup of the downloaded script.
$renewalScript = Join-Path $StateFolder "update_policy_changer.ps1"
Copy-Item -Path $PSCommandPath -Destination $renewalScript -Force

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$renewalScript`" -Renewal"
$atStartup = New-ScheduledTaskTrigger -AtStartup
$weekly    = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "03:00AM"
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable `
    -DisallowStartIfOnBatteries:$false -RestartCount 5 -RestartInterval "PT1M"
Register-ScheduledTask -TaskName $TaskName -Action $action `
    -Trigger @($atStartup, $weekly) -Principal $principal -Settings $settings `
    -Description "KiWin: keep the Windows Update policy in line with the installed release and its end of servicing." `
    -Force | Out-Null
Write-Host "Renewal task '$TaskName' registered."

Write-Host "Done. Windows stays on its current feature release until near its end of servicing; cumulative updates arrive 4 days late."
