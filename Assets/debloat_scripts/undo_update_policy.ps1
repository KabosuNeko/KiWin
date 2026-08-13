# Undo Update Policy Changer
# filename: undo_update_policy.ps1
#
# Removes the Windows Update policy set by update_policy_changer.ps1 /
# update_policy_changer_pro.ps1 so the system receives full Windows updates again.
#
# NOTE: This only removes the policy values that KiWin sets. Other policy values
# under the same registry key (if any) are left untouched.

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator rights required." -ForegroundColor Red
    exit 1
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
    exit 0
}

foreach ($Name in $ValuesToRemove) {
    if (Get-ItemProperty -Path $RegPath -Name $Name -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $RegPath -Name $Name -Force
        Write-Host "Removed: $Name"
    }
}

# If the key is now empty, remove it entirely
$remaining = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
if ($remaining -and $remaining.PSObject.Properties.Count -eq 1) {
    Remove-Item -Path $RegPath -Force -Recurse
    Write-Host "Removed empty policy key: $RegPath"
}

# Restart Windows Update service so changes take effect
Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue

Write-Host "`nUpdate policy removed. Windows will now receive full updates again."