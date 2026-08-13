# Undo Update Policy Changer
# filename: undo_update_policy.ps1
#
# Removes the Windows Update policy set by update_policy_changer.ps1 so the
# system receives full Windows updates again.
#
# Also removes the automatic renewal scheduled task and helper files created by
# update_policy_changer.ps1 (DTLegit-style annual reapply), otherwise the policy
# would be silently re-applied later. Both the current (WindowsUpdateSettingsTask)
# and legacy (CheckSecuritySettings / ReapplySecuritySettings) task names and
# helper folders are cleaned up.
#
# NOTE: This only removes the policy values that KiWin sets. Other policy values
# under the same registry keys (if any) are left untouched.

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator rights required." -ForegroundColor Red
    exit 1
}

# Remove the automatic renewal scheduled tasks and helper files first
$UpdateTasks = @("WindowsUpdateSettingsTask", "CheckSecuritySettings", "ReapplySecuritySettings")
foreach ($TaskName in $UpdateTasks) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed scheduled task: $TaskName"
    }
}

$HelperFolders = @(
    "C:\ProgramData\Windows Updates Settings",
    "C:\ProgramData\UpdateWindowsUpdatePoliciesAnnually"
)
foreach ($HelperFolder in $HelperFolders) {
    if (Test-Path $HelperFolder) {
        Remove-Item -Path $HelperFolder -Recurse -Force
        Write-Host "Removed helper folder: $HelperFolder"
    }
}

$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

$ValuesToRemove = @(
    "DeferQualityUpdates",
    "DeferQualityUpdatesPeriodInDays",
    "ProductVersion",
    "TargetReleaseVersion",
    "TargetReleaseVersionInfo",
    "ExcludeUpdateClassifications",
    "ExcludeWUDriversInQualityUpdate",
    "AUOptions"
)

if (-not (Test-Path $RegPath)) {
    Write-Host "Update policy key not found. Nothing to undo."
}
else {
    foreach ($Name in $ValuesToRemove) {
        if (Get-ItemProperty -Path $RegPath -Name $Name -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $RegPath -Name $Name -Force
            Write-Host "Removed: $Name"
        }
    }

    # Remove the AU subkey created by update_policy_changer.ps1 (AUPowerManagement)
    $AUSubkey = Join-Path $RegPath "AU"
    if (Test-Path $AUSubkey) {
        $AuRemaining = Get-ItemProperty -Path $AUSubkey -ErrorAction SilentlyContinue
        if ($AuRemaining -and $AuRemaining.PSObject.Properties.Count -eq 1) {
            Remove-Item -Path $AUSubkey -Force -Recurse
            Write-Host "Removed empty AU subkey: $AUSubkey"
        }
        else {
            Remove-ItemProperty -Path $AUSubkey -Name "AUPowerManagement" -Force -ErrorAction SilentlyContinue
            Write-Host "Removed: AUPowerManagement (AU)"
        }
    }

    # If the key is now empty, remove it entirely
    $remaining = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
    if ($remaining -and $remaining.PSObject.Properties.Count -eq 1) {
        Remove-Item -Path $RegPath -Force -Recurse
        Write-Host "Removed empty policy key: $RegPath"
    }
}

# Remove the UX\Settings values set by update_policy_changer.ps1
# (restores Windows' default active hours behavior)
$UXRegPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
if (Test-Path $UXRegPath) {
    $UXValuesToRemove = @(
        "ActiveHoursEnd",
        "ActiveHoursStart",
        "AllowMUUpdateService",
        "SmartActiveHoursState",
        "UserChoiceActiveHoursStart",
        "UserChoiceActiveHoursEnd"
    )
    foreach ($Name in $UXValuesToRemove) {
        if (Get-ItemProperty -Path $UXRegPath -Name $Name -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $UXRegPath -Name $Name -Force
            Write-Host "Removed: $Name (UX)"
        }
    }
}

# Restart Windows Update service so changes take effect
Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue

Write-Host "`nUpdate policy removed. Windows will now receive full updates again."