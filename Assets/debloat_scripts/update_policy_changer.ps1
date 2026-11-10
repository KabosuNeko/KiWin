# Keeps Windows on the installed feature release (no feature upgrades) and
# delays monthly cumulative updates by 4 days. Cumulative updates still
# install, so this is not "security only": they carry non-security fixes too.
# The pinned release keeps getting updates only until its end of servicing
# (e.g. 24H2 Home/Pro: October 2026); after that, run undo_update_policy.ps1.
# Drivers from Windows Update are left alone.
# A SYSTEM task re-applies the policy every 364 days. Original implementation;
# the deferral technique follows DTLegit's FullWinUpdate-Disabler.

param(
    [switch]$Renewal
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator rights required." -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = "Continue"

$TaskName        = "KiWinUpdatePolicyRenewal"
$StateFolder     = "C:\ProgramData\KiWin\UpdatePolicy"
$TimestampFile   = Join-Path $StateFolder "LastApplied.txt"
$RenewalPeriod   = 364

$WuPolicyPath    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$WuAutoPath      = "$WuPolicyPath\AU"
$WuUxPath        = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

function Get-TimestampAgeDays {
    if (-not (Test-Path $TimestampFile)) { return [int]::MaxValue }
    try {
        $last = Get-Date (Get-Content $TimestampFile -Raw).Trim() -ErrorAction Stop
        return [int]((New-TimeSpan -Start $last -End (Get-Date)).TotalDays)
    }
    catch {
        return [int]::MaxValue
    }
}

function Ensure-RegKey {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function Assert-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    Ensure-RegKey $Path
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

function Get-FeatureRelease {
    $p = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
    foreach ($value in $p.DisplayVersion, $p.ReleaseId) {
        if ($value -match "^\d{2}H\d$") { return [string]$value }
    }
}

function Set-KiWinUpdatePolicy {
    $changed = $false

    $product = if ([Environment]::OSVersion.Version.Build -ge 22000) { "Windows 11" } else { "Windows 10" }
    if (Assert-RegValue $WuPolicyPath "ProductVersion" $product "String") { $changed = $true }

    $release = Get-FeatureRelease
    if ($release) {
        if (Assert-RegValue $WuPolicyPath "TargetReleaseVersion" 1) { $changed = $true }
        if (Assert-RegValue $WuPolicyPath "TargetReleaseVersionInfo" $release "String") { $changed = $true }
    }
    else {
        # Drop a stale pin instead of leaving the machine on an old release.
        foreach ($name in "TargetReleaseVersion", "TargetReleaseVersionInfo") {
            if (Get-ItemProperty -Path $WuPolicyPath -Name $name -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $WuPolicyPath -Name $name -Force
                $changed = $true
            }
        }
        Write-Warning "Could not detect the feature release; feature updates are not pinned."
    }
    if (Assert-RegValue $WuPolicyPath "DeferQualityUpdates" 1) { $changed = $true }
    if (Assert-RegValue $WuPolicyPath "DeferQualityUpdatesPeriodInDays" 4) { $changed = $true }
    # Older KiWin versions blocked drivers, which leaves fresh installs without them.
    $drivers = Get-ItemProperty -Path $WuPolicyPath -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue
    if ($null -ne $drivers -and $drivers.ExcludeWUDriversInQualityUpdate -eq 1) {
        Remove-ItemProperty -Path $WuPolicyPath -Name "ExcludeWUDriversInQualityUpdate" -Force
        Write-Host "Removed ExcludeWUDriversInQualityUpdate (drivers from Windows Update are allowed again)"
        $changed = $true
    }

    if (Assert-RegValue $WuAutoPath "AUPowerManagement" 0) { $changed = $true }

    if (Assert-RegValue $WuUxPath "ActiveHoursStart" 8) { $changed = $true }
    if (Assert-RegValue $WuUxPath "ActiveHoursEnd" 2) { $changed = $true }
    if (Assert-RegValue $WuUxPath "AllowMUUpdateService" 0) { $changed = $true }
    if (Assert-RegValue $WuUxPath "SmartActiveHoursState" 0) { $changed = $true }
    if (Assert-RegValue $WuUxPath "UserChoiceActiveHoursStart" 8) { $changed = $true }
    if (Assert-RegValue $WuUxPath "UserChoiceActiveHoursEnd" 2) { $changed = $true }

    if ($changed) {
        gpupdate /force | Out-Null
        New-Item -ItemType Directory -Path $StateFolder -Force | Out-Null
        (Get-Date).ToString("o") | Set-Content -Path $TimestampFile -Encoding UTF8
        Write-Host "Update policy applied."
    }
    else {
        Write-Host "Update policy already up to date."
    }
}

if ($Renewal) {
    $age = Get-TimestampAgeDays
    if ($age -lt $RenewalPeriod) {
        Write-Host "Policy last applied $age days ago; nothing to do."
        exit 0
    }
    Write-Host "Policy last applied $age days ago; re-applying."
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

# Secure the folder before anything (timestamp, script copy) is written into it.
try {
    Protect-StateFolder (Split-Path $StateFolder -Parent)
    Protect-StateFolder $StateFolder
}
catch {
    Write-Host "Could not secure ${StateFolder}: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Set-KiWinUpdatePolicy

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
    -Description "KiWin: re-apply the Windows Update policy once it is older than 364 days." `
    -Force | Out-Null
Write-Host "Renewal task '$TaskName' registered."

Write-Host "Done. Windows stays on its current feature release; cumulative updates arrive 4 days late."