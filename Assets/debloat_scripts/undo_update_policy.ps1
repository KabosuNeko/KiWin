# Removes the policy set by update_policy_changer.ps1, its renewal task, and
# its helper files; otherwise the policy gets re-applied silently later.
# Values under the same keys that KiWin did not set are left alone.

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator rights required." -ForegroundColor Red
    exit 1
}

$UpdateTasks = @("KiWinUpdatePolicyRenewal", "WindowsUpdateSettingsTask", "CheckSecuritySettings", "ReapplySecuritySettings")
foreach ($TaskName in $UpdateTasks) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed scheduled task: $TaskName"
    }
}

$HelperFolders = @(
    "C:\ProgramData\KiWin\UpdatePolicy",
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

    $AUSubkey = Join-Path $RegPath "AU"
    if (Test-Path $AUSubkey) {
        Remove-ItemProperty -Path $AUSubkey -Name "AUPowerManagement" -Force -ErrorAction SilentlyContinue
        $AUKey = Get-Item -LiteralPath $AUSubkey -ErrorAction SilentlyContinue
        if ($AUKey -and -not $AUKey.GetValueNames() -and -not $AUKey.GetSubKeyNames()) {
            Remove-Item -LiteralPath $AUSubkey -Force -Recurse
            Write-Host "Removed empty AU subkey: $AUSubkey"
        }
        else {
            Write-Host "Removed: AUPowerManagement (AU)"
        }
    }

    $PolicyKey = Get-Item -LiteralPath $RegPath -ErrorAction SilentlyContinue
    if ($PolicyKey -and -not $PolicyKey.GetValueNames() -and -not $PolicyKey.GetSubKeyNames()) {
        Remove-Item -LiteralPath $RegPath -Force -Recurse
        Write-Host "Removed empty policy key: $RegPath"
    }
}

# Restores Windows' default active hours.
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

Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue

Write-Host "`nUpdate policy removed. Windows will now receive full updates again."