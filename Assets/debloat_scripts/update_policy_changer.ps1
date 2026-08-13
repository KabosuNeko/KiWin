# Update Policy Changer
# filename: update_policy_changer.ps1
#
# Limits Windows to security-related (quality) updates for the currently running
# feature release, blocking feature updates. Works on both Home and Pro editions.
# The block is renewed automatically via a scheduled task (startup + weekly) so it
# stays in place on Windows Home past the 365-day deferral limit.
#
# Also applies:
#  - ExcludeWUDriversInQualityUpdate: drivers are no longer installed through
#    Windows Update (use vendor updaters instead).
#  - Active hours 08:00 - 02:00: the PC only restarts automatically during the
#    early morning window (02:00 - 08:00).
#
# Based on DTLegit/FullWinUpdate-Disabler (SecurityOnlyV3.ps1).
# Special thanks to DTLegit.

# ----- Function: Test for Administrator Privileges -----
function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# If not running as Administrator, relaunch the script with elevated rights.
if (-not (Test-Admin)) {
    Write-Host "Master script is not running as Administrator. Relaunching as Administrator..."
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

# ----- Define Folder and File Paths -----
$MainFolder    = "C:\ProgramData\Windows Updates Settings"
$LogFolder     = Join-Path $MainFolder "Logs"
$TimestampFile = Join-Path $MainFolder "LastRunTimestamp.txt"
$ChildScript   = Join-Path $MainFolder "RunWindowsUpdateSettings.ps1"

# Create the main folder if it does not exist.
if (-not (Test-Path $MainFolder)) {
    New-Item -Path $MainFolder -ItemType Directory -Force | Out-Null
}
# Create the Logs folder if it does not exist.
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

# ----- Create the Child Script -----
# The child script contains the core function to check and apply Windows Update settings.
$childScriptContent = @'
# ================================================================
# RunWindowsUpdateSettings.ps1
# ================================================================
# This script checks and applies Windows Update security settings if needed.
#
# It performs the following:
# 1. Checks if this is the first run or if at least 364 days have elapsed
#    since the last update (using a timestamp file).
# 2. Detects the OS version (Windows 10 vs. Windows 11) and the major feature release.
# 3. Validates registry settings for Windows Update, Device Metadata,
#    Driver Searching, and WindowsUpdate\AU.
# 4. If discrepancies are found or it is the first run, applies the proper registry settings,
#    forces a gpupdate, and updates the timestamp.
# 5. Logs all actions to a log file in the Logs folder (keeping only the last 3 logs).
# ================================================================

param()

# ----- Start Logging -----
$LogFolder = Join-Path "C:\ProgramData\Windows Updates Settings" "Logs"
$TimeStampNow = (Get-Date).ToString("yyyyMMddHHmmss")
$LogFile = Join-Path $LogFolder ("WindowsUpdateSettings-$TimeStampNow.log")
try {
    Start-Transcript -Path $LogFile -Append | Out-Null
}
catch {
    Write-Host "WARNING: Failed to start transcript: $_"
}

$TimestampFile = Join-Path "C:\ProgramData\Windows Updates Settings" "LastRunTimestamp.txt"

# ----- Determine if Initial Run or 364+ Days Have Passed -----
$InitialRun = $false
if (-not (Test-Path $TimestampFile)) {
    Write-Host "Timestamp file not found. Assuming initial run."
    $InitialRun = $true
} else {
    $LastRunStr = Get-Content $TimestampFile -ErrorAction SilentlyContinue
    try {
        $LastRun = Get-Date $LastRunStr -ErrorAction Stop
    }
    catch {
        Write-Host "DEBUG: Failed to parse timestamp '$LastRunStr'. Treating as initial run."
        $InitialRun = $true
    }
}

if (-not $InitialRun) {
    $CurrentDate = Get-Date
    $TimeSpan = New-TimeSpan -Start $LastRun -End $CurrentDate
    Write-Host ("DEBUG: Elapsed time since last run: {0} days, {1} hours, {2} minutes, {3} seconds." `
        -f $TimeSpan.Days, $TimeSpan.Hours, $TimeSpan.Minutes, $TimeSpan.Seconds)
}

if ($InitialRun -or ($TimeSpan.TotalDays -ge 364)) {
    Write-Host "Proceeding to verify and apply Windows Update security settings..."

    # ----- OS and Feature Release Detection -----
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -eq 10 -and $osVersion.Build -ge 22000) {
        $ProductVersion = "Windows 11"
    }
    elseif ($osVersion.Major -eq 10) {
        $ProductVersion = "Windows 10"
    }
    else {
        $ProductVersion = "Unknown"
    }
    Write-Host "DEBUG: Detected OS: $ProductVersion (Build $($osVersion.Build))"

    # Determine Feature Release via layered detection.
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $primaryFeatureRelease = $null
    $secondaryFeatureRelease = $null
    $tertiaryFeatureRelease = $null
    try { $regValues = Get-ItemProperty -Path $regPath -ErrorAction Stop } catch { }
    if ($regValues -and $regValues.DisplayVersion) {
        if ($regValues.DisplayVersion -match "^\d{2}H\d$") {
            $primaryFeatureRelease = $regValues.DisplayVersion
            Write-Host "DEBUG: Primary Feature Release: $primaryFeatureRelease"
        } else {
            Write-Host "DEBUG: DisplayVersion format mismatch."
        }
    } else {
        Write-Host "DEBUG: DisplayVersion not found."
    }
    try { $osInfo = Get-ComputerInfo -ErrorAction Stop } catch { }
    if ($osInfo -and $osInfo.OSDisplayVersion) {
        if ($osInfo.OSDisplayVersion -match "^\d{2}H\d$") {
            $secondaryFeatureRelease = $matches[0]
            Write-Host "DEBUG: Secondary Feature Release: $secondaryFeatureRelease"
        } else {
            Write-Host "DEBUG: OSDisplayVersion format mismatch."
        }
    } else {
        Write-Host "DEBUG: OSDisplayVersion not found."
    }
    if (-not $primaryFeatureRelease -and $regValues -and $regValues.ReleaseId) {
        if ($regValues.ReleaseId -match "^\d{2}H\d$") {
            $tertiaryFeatureRelease = $regValues.ReleaseId
            Write-Host "DEBUG: Tertiary Feature Release: $tertiaryFeatureRelease"
        } else {
            Write-Host "DEBUG: ReleaseId format mismatch."
        }
    }
    $finalFeatureRelease = $primaryFeatureRelease
    if (-not $finalFeatureRelease) { $finalFeatureRelease = $secondaryFeatureRelease }
    if (-not $finalFeatureRelease) { $finalFeatureRelease = $tertiaryFeatureRelease }
    if ($finalFeatureRelease) {
        $TargetReleaseVersionInfo = $finalFeatureRelease
        Write-Host "DEBUG: Final Feature Release: $TargetReleaseVersionInfo"
    } else {
        $TargetReleaseVersionInfo = "24H2"
        Write-Host "DEBUG: No valid feature release detected; defaulting to $TargetReleaseVersionInfo"
    }

    # ----- Registry Settings Verification & Application -----
    $ReapplyNeeded = $false

    # --- Check WindowsUpdate Policy Key ---
    $WURegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $WUSettings = Get-ItemProperty -Path $WURegPath -ErrorAction SilentlyContinue
    if (-not $WUSettings) {
        Write-Host "DEBUG: WindowsUpdate key not found; it will be created."
        $ReapplyNeeded = $true
    }
    elseif (($WUSettings.ProductVersion -ne $ProductVersion) -or
            ($WUSettings.TargetReleaseVersionInfo -ne $TargetReleaseVersionInfo) -or
            ($WUSettings.TargetReleaseVersion -ne 1) -or
            ($WUSettings.DeferQualityUpdates -ne 1) -or
            ($WUSettings.DeferQualityUpdatesPeriodInDays -ne 4) -or
            ($WUSettings.ExcludeWUDriversInQualityUpdate -ne 1)) {
        Write-Host "DEBUG: WindowsUpdate registry discrepancy detected."
        $ReapplyNeeded = $true
    }

    # --- Check WindowsUpdate UX\Settings Key ---
    $UXRegPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
    $UXSettings = Get-ItemProperty -Path $UXRegPath -ErrorAction SilentlyContinue
    if (-not $UXSettings) {
        Write-Host "DEBUG: WindowsUpdate UX\Settings key not found; it will be created."
        $ReapplyNeeded = $true
    }
    else {
        if (($UXSettings.ActiveHoursEnd -ne 2) -or
            ($UXSettings.ActiveHoursStart -ne 8) -or
            ($UXSettings.AllowMUUpdateService -ne 0) -or
            ($UXSettings.SmartActiveHoursState -ne 0) -or
            ($UXSettings.UserChoiceActiveHoursStart -ne 8) -or
            ($UXSettings.UserChoiceActiveHoursEnd -ne 2)) {
            Write-Host "DEBUG: WindowsUpdate UX\Settings registry discrepancy detected."
            $ReapplyNeeded = $true
        }
    }

    # ----- Apply Registry Settings if Needed -----
    if ($InitialRun -or $ReapplyNeeded) {
        Write-Host "Applying registry settings..."

        # --- Apply settings for WindowsUpdate key ---
        $RegistrySettings = @{
            "ProductVersion"                  = $ProductVersion
            "TargetReleaseVersion"            = 1
            "TargetReleaseVersionInfo"        = $TargetReleaseVersionInfo
            "DeferQualityUpdates"             = 1
            "DeferQualityUpdatesPeriodInDays" = 4
            "ExcludeWUDriversInQualityUpdate" = 1
        }
        if (-not (Test-Path $WURegPath)) { New-Item -Path $WURegPath -Force | Out-Null }
        foreach ($Name in $RegistrySettings.Keys) {
            $Value = $RegistrySettings[$Name]
            $Type = if ($Value -is [int]) { "DWord" } else { "String" }
            try {
                $existingValue = Get-ItemProperty -Path $WURegPath -Name $Name -ErrorAction SilentlyContinue
                if ($null -eq $existingValue) {
                    New-ItemProperty -Path $WURegPath -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
                } else {
                    Set-ItemProperty -Path $WURegPath -Name $Name -Value $Value -Force
                }
                Write-Host "Set $Name to $Value ($Type)"
            } catch {
                Write-Host "Failed to set ${Name}: $_" -ForegroundColor Red
            }
        }

        # --- Create and Configure WindowsUpdate\AU Key ---
        $AUKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (-not (Test-Path $AUKey)) {
            New-Item -Path $AUKey -Force | Out-Null
            Write-Host "DEBUG: Created AU subkey under WindowsUpdate."
        }

        Set-ItemProperty -Path $AUKey -Name "AUPowerManagement" -Type DWord -Value 0
        Write-Host "Applied WindowsUpdate AU settings."

        # --- Configure WindowsUpdate UX\Settings Key ---
        $UXRegistrySettings = @{
            "ActiveHoursEnd"            = 2
            "ActiveHoursStart"          = 8
            "AllowMUUpdateService"      = 0
            "SmartActiveHoursState"     = 0
            "UserChoiceActiveHoursStart"= 8
            "UserChoiceActiveHoursEnd"  = 2
        }
        if (-not (Test-Path $UXRegPath)) { New-Item -Path $UXRegPath -Force | Out-Null }
        foreach ($Name in $UXRegistrySettings.Keys) {
            $Value = $UXRegistrySettings[$Name]
            $Type  = "DWord"  # All are DWORD values
            try {
                $existingValue = Get-ItemProperty -Path $UXRegPath -Name $Name -ErrorAction SilentlyContinue
                if ($null -eq $existingValue) {
                    New-ItemProperty -Path $UXRegPath -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
                } else {
                    Set-ItemProperty -Path $UXRegPath -Name $Name -Value $Value -Force
                }
                Write-Host "Set $Name to $Value ($Type)"
            } catch {
                Write-Host "Failed to set ${Name}: $_" -ForegroundColor Red
            }
        }

        gpupdate /force
        Write-Host "Registry settings applied."
        (Get-Date).ToString("o") | Out-File -FilePath $TimestampFile -Encoding UTF8
        Write-Host "Timestamp updated."
    }
    else {
        Write-Host "Registry settings are up-to-date. No changes applied."
    }
} else {
    Write-Host "No update required at this time."
}

# ----- Clean Up Old Logs (Keep Only Last 3) -----
try {
    $logs = Get-ChildItem -Path $LogFolder -Filter "WindowsUpdateSettings-*.log" | Sort-Object CreationTime -Descending
    $oldLogs = $logs | Select-Object -Skip 3
    foreach ($log in $oldLogs) { Remove-Item $log.FullName -Force }
}
catch { Write-Host "WARNING: Failed to clean old logs: $_" }

try { Stop-Transcript | Out-Null } catch { }
'@

# Save the child script to disk.
Set-Content -Path $ChildScript -Value $childScriptContent -Force -Encoding UTF8

# ----- Register Scheduled Task -----
# This scheduled task will run the child script with a temporary Unrestricted execution policy.
$TaskName = "WindowsUpdateSettingsTask"
$TaskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Unrestricted -WindowStyle Hidden -File `"$ChildScript`""
$TriggerStartup = New-ScheduledTaskTrigger -AtStartup
$TriggerWeekly  = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "03:00AM"
$Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$TaskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8
$TaskSettings.StartWhenAvailable = $true
$TaskSettings.DisallowStartIfOnBatteries = $false
# Set task to restart every 1 minute up to 5 times if it fails.
$TaskSettings.RestartInterval = [System.Xml.XmlConvert]::ToString((New-TimeSpan -Minutes 1))
$TaskSettings.RestartCount = 5

Register-ScheduledTask -TaskName $TaskName `
                       -Action $TaskAction `
                       -Trigger @($TriggerStartup, $TriggerWeekly) `
                       -Principal $Principal `
                       -Settings $TaskSettings `
                       -Description "Runs the child script to check and apply Windows Update security settings if needed." `
                       -Force

Write-Host "Scheduled task '$TaskName' registered."

# ----- Run the Child Script Immediately for Initial Setup -----
Write-Host "Running initial application of Windows Update security settings..."
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Unrestricted -File `"$ChildScript`"" -Verb RunAs -Wait
Write-Host "Initial Windows Update security settings applied!"
