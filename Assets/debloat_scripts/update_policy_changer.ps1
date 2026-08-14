# KiWin Update Policy Changer
# filename: update_policy_changer.ps1
#
# Restricts Windows Update to security (quality) updates for the currently
# running feature release, blocking feature updates. Works on both Home and
# Pro editions. A SYSTEM scheduled task re-applies the settings once they are
# older than 364 days, which keeps the block in place on Windows Home past the
# 365-day deferral limit.
#
# Also applies:
#  - ExcludeWUDriversInQualityUpdate: drivers are no longer installed through
#    Windows Update (use vendor updaters instead).
#  - Active hours 08:00 - 02:00: the PC only restarts automatically during the
#    early morning window (02:00 - 08:00).
#
# The registry technique (defer quality updates + pin feature release) follows
# the approach popularized by DTLegit's FullWinUpdate-Disabler; this file is an
# original implementation.

param(
    [switch]$Renewal
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator rights required." -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = "Continue"

# ----- Constants -----
$TaskName        = "KiWinUpdatePolicyRenewal"
$StateFolder     = "C:\ProgramData\KiWin\UpdatePolicy"
$TimestampFile   = Join-Path $StateFolder "LastApplied.txt"
$RenewalPeriod   = 364

# ----- Registry targets -----
$WuPolicyPath    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$WuAutoPath      = "$WuPolicyPath\AU"
$WuUxPath        = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

# ----- Helpers -----
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

function Get-ProductVersion {
    $os = [System.Environment]::OSVersion.Version
    if ($os.Build -ge 22000) { return "Windows 11" }
    if ($os.Build -ge 10240) { return "Windows 10" }
    $k = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
    if ($p -and $p.ProductName) { return [string]$p.ProductName }
    return "Windows"
}

function Detect-FeatureRelease {
    $candidates = New-Object System.Collections.Generic.List[string]
    $k = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    try { $p = Get-ItemProperty -Path $k -ErrorAction Stop } catch { $p = $null }
    if ($p) {
        if ($p.DisplayVersion -match "^\d{2}H\d$") { $candidates.Add([string]$p.DisplayVersion) }
        if ($p.ReleaseId -match "^\d{2}H\d$") { $candidates.Add([string]$p.ReleaseId) }
    }
    try { $ci = Get-ComputerInfo -ErrorAction Stop } catch { $ci = $null }
    if ($ci -and $ci.OSDisplayVersion -match "^\d{2}H\d$") { $candidates.Add([string]$ci.OSDisplayVersion) }
    foreach ($c in $candidates) {
        if ($c -and ($c -notmatch "\s")) { return $c }
    }
    Write-Host "Could not detect feature release; falling back to 24H2." -ForegroundColor Yellow
    return "24H2"
}

function Set-KiWinUpdatePolicy {
    $changed = $false

    # ---- WindowsUpdate policy key ----
    $release = Detect-FeatureRelease
    if (Assert-RegValue $WuPolicyPath "ProductVersion" ([string](Get-ProductVersion)) "String") { $changed = $true }
    if (Assert-RegValue $WuPolicyPath "TargetReleaseVersion" 1) { $changed = $true }
    if (Assert-RegValue $WuPolicyPath "TargetReleaseVersionInfo" $release "String") { $changed = $true }
    if (Assert-RegValue $WuPolicyPath "DeferQualityUpdates" 1) { $changed = $true }
    if (Assert-RegValue $WuPolicyPath "DeferQualityUpdatesPeriodInDays" 4) { $changed = $true }
    if (Assert-RegValue $WuPolicyPath "ExcludeWUDriversInQualityUpdate" 1) { $changed = $true }

    # ---- WindowsUpdate\AU subkey ----
    if (Assert-RegValue $WuAutoPath "AUPowerManagement" 0) { $changed = $true }

    # ---- UX\Settings (active hours) ----
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

# ----- Renewal check (scheduled task path) -----
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

# ----- Main (interactive / KiWin run) -----
Set-KiWinUpdatePolicy

# Copy the script to a system-wide location and register the renewal task
# against that copy, so the task keeps working even if the KiWin appdata
# folder is later removed or re-extracted.
New-Item -ItemType Directory -Path $StateFolder -Force | Out-Null
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
    -Description "KiWin: re-apply the security-only update policy once it is older than 364 days." `
    -Force | Out-Null
Write-Host "Renewal task '$TaskName' registered."

Write-Host "Done. Windows Update will deliver security updates only."