# Update Policy Changer
# filename: update_policy_changer.ps1
#
# Limits Windows Home to security updates, blocking feature updates.
# Prevents unwanted system changes and re-installed bloatware.
# Note: For Windows Pro or above, use the Pro variant for a permanent fix.
#
# Based on DTLegit/Windows-SecurityUpdates-Only-Script (SecurityUpdatesOnlyV2.ps1).
# Additional behavior over the original script:
#  - Pins Windows to the currently installed feature release (no stale 24H2 fallback).
#  - Registers a scheduled task (startup + weekly, SYSTEM) that detects a changed
#    feature release or expired 365-day deferral and re-applies the policy.
#
# Special thanks to DTLegit.

# ----- Function: Ensure running as Administrator -----
function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "Script is not running as Administrator. Relaunching as Administrator..."
    try {
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
            -Verb RunAs
    }
    catch {
        Write-Host "Failed to relaunch as Administrator. Please re-run this script manually as an Administrator." -ForegroundColor Red
    }
    exit
}

# ----- Define folder and file paths -----
$ScheduledFolder = "C:\ProgramData\UpdateWindowsUpdatePoliciesAnnually"
if (-not (Test-Path $ScheduledFolder)) {
    New-Item -Path $ScheduledFolder -ItemType Directory -Force | Out-Null
}

# Create a Logs folder for the two helper scripts
$LogFolder = Join-Path $ScheduledFolder "Logs"
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

$ApplyScriptPath = Join-Path $ScheduledFolder "ApplySecuritySettings.ps1"
$CheckScriptPath = Join-Path $ScheduledFolder "CheckSecuritySettings.ps1"
$TimestampFile   = Join-Path $ScheduledFolder "LastRunTimestamp.txt"

# ----- Create the ApplySecuritySettings.ps1 script -----
$ApplyScriptContent = @'
param(
    [switch]$Silent
)
# ===============================================
# ApplySecuritySettings.ps1
# ===============================================
# This script applies Windows Update registry policies:
#  - Deletes any pending "ReapplySecuritySettings" task.
#  - Detects OS version (Windows 10 vs. Windows 11) and the Windows feature release.
#  - Updates registry keys under HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate.
#  - Forces a gpupdate.
#  - Writes the current date/time to the timestamp file.
#  - Accepts a -Silent switch to suppress debug output.
#  - Logs to: C:\ProgramData\UpdateWindowsUpdatePoliciesAnnually\Logs
#     and keeps only the last 3 logs.
# ===============================================

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    if (-not $Silent) { Write-Host "ApplySecuritySettings.ps1 is not running as Administrator. Relaunching..." }
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    }
    catch {
        if (-not $Silent) { Write-Host "Failed to relaunch as Administrator. Please run manually as Admin." -ForegroundColor Red }
    }
    exit
}

# ----- Logging Setup -----
$MainFolder = "C:\ProgramData\UpdateWindowsUpdatePoliciesAnnually"
$LogFolder  = Join-Path $MainFolder "Logs"
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}
$TimeStamp         = (Get-Date).ToString("yyyyMMddHHmmss")
$LogFile           = Join-Path $LogFolder ("ApplySecuritySettings-$TimeStamp.log")

try {
    Start-Transcript -Path $LogFile -Append | Out-Null
} catch {
    if (-not $Silent) { Write-Host "WARNING: Failed to start transcript for ApplySecuritySettings.ps1: $_" }
}

# ----- Begin Script Logic -----

# 1. Delete the ReapplySecuritySettings task if it exists (suppress error if it doesn't)
schtasks.exe /Delete /TN "ReapplySecuritySettings" /F 2>$null | Out-Null

# 2. Layered OS & Feature Release Detection
if (-not $Silent) { Write-Host "DEBUG: Beginning layered OS detection..." }

$osVersion = [System.Environment]::OSVersion.Version
if ($osVersion.Major -eq 10 -and $osVersion.Build -ge 22000) {
    $ProductVersion = "Windows 11"
} elseif ($osVersion.Major -eq 10) {
    $ProductVersion = "Windows 10"
} else {
    $ProductVersion = "Unknown"
}
if (-not $Silent) {
    Write-Host "DEBUG: System.Environment OSVersion: $osVersion"
    Write-Host "DEBUG: Detected OS: $ProductVersion (Build $($osVersion.Build))"
}

$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$primaryFeatureRelease   = $null
$secondaryFeatureRelease = $null
$tertiaryFeatureRelease  = $null

# Try to read registry values
$regValues = $null
try {
    $regValues = Get-ItemProperty -Path $regPath -ErrorAction Stop
} catch { }

# Primary: DisplayVersion
if ($regValues -and $regValues.DisplayVersion) {
    if ($regValues.DisplayVersion -match "^\d{2}H\d$") {
        $primaryFeatureRelease = $regValues.DisplayVersion
        if (-not $Silent) { Write-Host "DEBUG: Primary Feature Release (DisplayVersion): $primaryFeatureRelease" }
    } else {
        if (-not $Silent) { Write-Host "DEBUG: DisplayVersion '$($regValues.DisplayVersion)' not matching ^\d{2}H\d$" }
    }
} else {
    if (-not $Silent) { Write-Host "DEBUG: DisplayVersion not found in registry." }
}

# Secondary: OSDisplayVersion via Get-ComputerInfo
$osInfo = $null
try {
    $osInfo = Get-ComputerInfo -ErrorAction Stop
} catch { }

if ($osInfo -and $osInfo.OSDisplayVersion) {
    if ($osInfo.OSDisplayVersion -match "^\d{2}H\d$") {
        $secondaryFeatureRelease = $matches[0]
        if (-not $Silent) { Write-Host "DEBUG: Secondary Feature Release (OSDisplayVersion): $secondaryFeatureRelease" }
    } else {
        if (-not $Silent) { Write-Host "DEBUG: OSDisplayVersion '$($osInfo.OSDisplayVersion)' not matching ^\d{2}H\d$" }
    }
} else {
    if (-not $Silent) { Write-Host "DEBUG: OSDisplayVersion not found from Get-ComputerInfo." }
}

# Tertiary: ReleaseId (if primary is null)
if (-not $primaryFeatureRelease -and $regValues -and $regValues.ReleaseId) {
    if ($regValues.ReleaseId -match "^\d{2}H\d$") {
        $tertiaryFeatureRelease = $regValues.ReleaseId
        if (-not $Silent) { Write-Host "DEBUG: Tertiary Feature Release (ReleaseId): $tertiaryFeatureRelease" }
    } else {
        if (-not $Silent) { Write-Host "DEBUG: ReleaseId '$($regValues.ReleaseId)' not matching ^\d{2}H\d$" }
    }
}

# Decide final feature release
$finalFeatureRelease = $primaryFeatureRelease
if (-not $finalFeatureRelease) {
    $finalFeatureRelease = $secondaryFeatureRelease
    if (-not $finalFeatureRelease) {
        $finalFeatureRelease = $tertiaryFeatureRelease
    }
}

if ($finalFeatureRelease) {
    $TargetReleaseVersionInfo = $finalFeatureRelease
    if (-not $Silent) { Write-Host "DEBUG: Final Detected Feature Release: $TargetReleaseVersionInfo" }
} else {
    $TargetReleaseVersionInfo = "24H2"  # fallback
    if (-not $Silent) { Write-Host "DEBUG: No valid feature release detected; defaulting to $TargetReleaseVersionInfo" }
}

# 3. Apply Registry Settings
$WURegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$RegistrySettings = @{
    "ProductVersion"                  = $ProductVersion
    "TargetReleaseVersion"            = 1
    "TargetReleaseVersionInfo"        = $TargetReleaseVersionInfo
    "DeferQualityUpdates"             = 1
    "DeferQualityUpdatesPeriodInDays" = 4
}

if (-not (Test-Path $WURegPath)) {
    New-Item -Path $WURegPath -Force | Out-Null
}

foreach ($Name in $RegistrySettings.Keys) {
    $Value = $RegistrySettings[$Name]
    $Type = if ($Value -is [int]) { "DWord" } else { "String" }
    try {
        Set-ItemProperty -Path $WURegPath -Name $Name -Value $Value -Type $Type -Force
        if (-not $Silent) { Write-Host "Set $Name to $Value ($Type)" }
    }
    catch {
        if (-not $Silent) { Write-Host "Failed to set ${Name}: $_" -ForegroundColor Red }
    }
}

gpupdate /force | Out-Null
if (-not $Silent) { Write-Host "Registry settings applied successfully." }

# 4. Update Timestamp File
$TimestampFile = Join-Path $MainFolder "LastRunTimestamp.txt"
(Get-Date).ToString("o") | Out-File -FilePath $TimestampFile -Encoding UTF8
if (-not $Silent) { Write-Host "Timestamp updated to current date/time." }

# 5. Stop Transcript & Clean Up Old Logs
try {
    Stop-Transcript | Out-Null
} catch {
    # no-op
}

# Remove older logs (keep only last 3)
try {
    $logs = Get-ChildItem -Path $LogFolder -Filter "ApplySecuritySettings-*.log" | Sort-Object CreationTime -Descending
    $oldLogs = $logs | Select-Object -Skip 3
    foreach ($log in $oldLogs) {
        Remove-Item $log.FullName -Force
    }
} catch {
    if (-not $Silent) { Write-Host "WARNING: Failed to clean old ApplySecuritySettings logs: $_" }
}
'@

Set-Content -Path $ApplyScriptPath -Value $ApplyScriptContent -Force -Encoding UTF8

# ----- Create the CheckSecuritySettings.ps1 script -----
$CheckScriptContent = @'
param(
    [switch]$Silent
)
# ===============================================
# CheckSecuritySettings.ps1
# ===============================================
# This script checks if security settings need reapplication.
# It:
#  - Reads the timestamp file and calculates the elapsed time.
#  - Performs OS and feature-release detection (simplified version).
#  - Checks if the registry settings are missing or differ from expected values.
#  - If at least 364 days have elapsed or discrepancy found, schedules ReapplySecuritySettings.
#  - Accepts a -Silent switch to suppress debug output.
#  - Logs to: C:\ProgramData\UpdateWindowsUpdatePoliciesAnnually\Logs
#     and keeps only the last 3 logs.
# ===============================================

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    if (-not $Silent) { Write-Host "CheckSecuritySettings.ps1 is not running as Administrator. Relaunching..." }
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    }
    catch {
        if (-not $Silent) { Write-Host "Failed to relaunch as Administrator. Please run manually as Admin." -ForegroundColor Red }
    }
    exit
}

# ----- Logging Setup -----
$MainFolder = "C:\ProgramData\UpdateWindowsUpdatePoliciesAnnually"
$LogFolder  = Join-Path $MainFolder "Logs"
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}
$TimeStamp = (Get-Date).ToString("yyyyMMddHHmmss")
$LogFile   = Join-Path $LogFolder ("CheckSecuritySettings-$TimeStamp.log")

try {
    Start-Transcript -Path $LogFile -Append | Out-Null
} catch {
    if (-not $Silent) { Write-Host "WARNING: Failed to start transcript for CheckSecuritySettings.ps1: $_" }
}

$TimestampFile   = Join-Path $MainFolder "LastRunTimestamp.txt"
$ApplyScriptPath = Join-Path $MainFolder "ApplySecuritySettings.ps1"

if (-not (Test-Path $TimestampFile)) {
    if (-not $Silent) { Write-Host "Timestamp file not found. Exiting check." }
    # stop transcript
    try { Stop-Transcript | Out-Null } catch {}
    return
}

# Read and debug the timestamp
$LastRunStr = Get-Content $TimestampFile -ErrorAction SilentlyContinue
$LastRun = $null
try {
    $LastRun = Get-Date $LastRunStr -ErrorAction Stop
} catch {
    if (-not $Silent) { Write-Host "DEBUG: Failed to parse timestamp: '$LastRunStr'" }
    # stop transcript
    try { Stop-Transcript | Out-Null } catch {}
    return
}
if (-not $Silent) { Write-Host "DEBUG: LastRun date: $LastRun" }

$CurrentDate = Get-Date
if (-not $Silent) { Write-Host "DEBUG: Current date: $CurrentDate" }
$TimeSpan = New-TimeSpan -Start $LastRun -End $CurrentDate
if (-not $Silent) {
    Write-Host ("DEBUG: Elapsed: {0} days, {1} hours, {2} minutes, {3} seconds." -f $TimeSpan.Days, $TimeSpan.Hours, $TimeSpan.Minutes, $TimeSpan.Seconds)
}

if ($TimeSpan.TotalDays -ge 364) {
    if (-not $Silent) { Write-Host "At least 364 days have elapsed. Checking OS and registry..." }

    # ----- OS Version Check -----
    $OSVersion = [System.Environment]::OSVersion.Version
    $Major = $OSVersion.Major
    $Build = $OSVersion.Build

    if ($Major -eq 10 -and $Build -ge 22000) {
        $ProductVersion = "Windows 11"
    } elseif ($Major -eq 10) {
        $ProductVersion = "Windows 10"
    } else {
        $ProductVersion = "Unknown"
    }
    if (-not $Silent) { Write-Host "DEBUG: Detected OS: $ProductVersion" }

    # ----- Feature Release Check (simplified fallback) -----
    $TargetReleaseVersionInfo = $null
    try {
        $OSInfo = Get-ComputerInfo -ErrorAction Stop
        if (-not $Silent) { Write-Host "DEBUG: WindowsVersion: $($OSInfo.WindowsVersion)" }
        if ($OSInfo.WindowsVersion -match "(\d{2}H\d)") {
            $TargetReleaseVersionInfo = $matches[1]
        }
    } catch {
        try {
            $regInfo = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
            if ($regInfo -and $regInfo.ReleaseId) {
                $TargetReleaseVersionInfo = $regInfo.ReleaseId
            }
        } catch {
            $TargetReleaseVersionInfo = "24H2"
        }
    }
    if (-not $TargetReleaseVersionInfo) {
        $TargetReleaseVersionInfo = "24H2"
    }
    if (-not $Silent) { Write-Host "DEBUG: Detected Release Version: $TargetReleaseVersionInfo" }

    # ----- Registry Check -----
    $RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $ExistingRegSettings = $null
    try {
        $ExistingRegSettings = Get-ItemProperty -Path $RegPath -ErrorAction Stop
    } catch {
        $ExistingRegSettings = $null
    }

    $ReapplyNeeded = $false
    if ($null -eq $ExistingRegSettings) {
        if (-not $Silent) { Write-Host "DEBUG: Registry settings not found." }
        $ReapplyNeeded = $true
    } else {
        # Compare ProductVersion and TargetReleaseVersionInfo
        if (($ExistingRegSettings.ProductVersion -ne $ProductVersion) -or
            ($ExistingRegSettings.TargetReleaseVersionInfo -ne $TargetReleaseVersionInfo)) {
            if (-not $Silent) { Write-Host "DEBUG: Registry discrepancy found." }
            $ReapplyNeeded = $true
        }
    }

    if ($ReapplyNeeded) {
        if (-not $Silent) { Write-Host "Scheduling ReapplySecuritySettings in 1 minute..." }
        $startTime = (Get-Date).AddMinutes(1)
        $startTimeStr = $startTime.ToString("HH:mm")
        $command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ApplyScriptPath`" -Silent"
        schtasks.exe /Create /TN "ReapplySecuritySettings" /TR $command /SC ONCE /ST $startTimeStr /RL HIGHEST /F | Out-Null
    } else {
        if (-not $Silent) { Write-Host "Registry settings are up-to-date. No reapply needed." }
    }
} else {
    if (-not $Silent) { Write-Host "Security settings update not required yet." }
}

# ----- Stop Transcript & Clean Up Old Logs -----
try {
    Stop-Transcript | Out-Null
} catch { }

try {
    $logs = Get-ChildItem -Path $LogFolder -Filter "CheckSecuritySettings-*.log" | Sort-Object CreationTime -Descending
    $oldLogs = $logs | Select-Object -Skip 3
    foreach ($log in $oldLogs) {
        Remove-Item $log.FullName -Force
    }
} catch {
    if (-not $Silent) { Write-Host "WARNING: Failed to clean old CheckSecuritySettings logs: $_" }
}
'@

Set-Content -Path $CheckScriptPath -Value $CheckScriptContent -Force -Encoding UTF8

# ----- Create or update the Timestamp file if it doesn't exist -----
if (-not (Test-Path $TimestampFile)) {
    (Get-Date).ToString("o") | Out-File -FilePath $TimestampFile -Encoding UTF8
}

# ----- Create the Scheduled Task for the Check Script -----
# This task runs at system startup and weekly (every Sunday at 03:00 AM)
$TriggerStartup = New-ScheduledTaskTrigger -AtStartup
$TriggerWeekly  = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "03:00AM"
$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$CheckScriptPath`" -Silent"

# Use SYSTEM account to run whether a user is logged on or not
$Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -Compatibility Win8

Register-ScheduledTask -TaskName "CheckSecuritySettings" `
                       -Action $Action `
                       -Trigger @($TriggerStartup, $TriggerWeekly) `
                       -Principal $Principal `
                       -Settings $settings `
                       -Description "Periodically checks and triggers reapplication of Windows Update security settings if needed." `
                       -Force

Write-Host "Setup complete. The CheckSecuritySettings task has been scheduled to run at startup and weekly under SYSTEM."

# ----- Run the ApplySecuritySettings.ps1 script immediately for initial setup -----
Write-Host "Running initial application of security settings..."
& "$ApplyScriptPath"

Write-Host "`nSecurity updates only. The policy will be renewed automatically."
