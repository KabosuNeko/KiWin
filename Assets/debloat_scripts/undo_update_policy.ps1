# Removes the policy set by update_policy_changer.ps1, its renewal task, and
# its helper files; otherwise the policy gets re-applied silently later.
# Values that existed before KiWin (saved in Original.json) are put back.
# Installs from older KiWin versions have no Original.json: their values are
# removed, which returns Windows to its defaults.

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator rights required." -ForegroundColor Red
    exit 1
}

$StateFolder  = "C:\ProgramData\KiWin\UpdatePolicy"
$OriginalFile = Join-Path $StateFolder "Original.json"
$RegPath      = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$AUSubkey     = Join-Path $RegPath "AU"
$UXRegPath    = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

# Stop the renewal first so it cannot re-apply the policy halfway through.
# The other names are tasks of DTLegit's script that older KiWin versions used.
$UpdateTasks = @("KiWinUpdatePolicyRenewal", "WindowsUpdateSettingsTask", "CheckSecuritySettings", "ReapplySecuritySettings")
foreach ($TaskName in $UpdateTasks) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed scheduled task: $TaskName"
    }
}

# Read the snapshot before the folder that holds it is deleted.
$original = $null
if (Test-Path -LiteralPath $OriginalFile) {
    try { $original = @(Get-Content -LiteralPath $OriginalFile -Raw | ConvertFrom-Json) }
    catch { Write-Warning "Original.json could not be read; values will be removed instead of restored." }
}

function Remove-ValueIfPresent {
    param([string]$Path, [string]$Name)
    if (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $Path -Name $Name -Force
        Write-Host "Removed: $Name"
    }
}

function Restore-Value {
    param($Entry)
    if (-not $Entry.Exists) {
        Remove-ValueIfPresent $Entry.Path $Entry.Name
        return
    }
    $kind = [Microsoft.Win32.RegistryValueKind]$Entry.Kind
    $value = switch ($kind) {
        # Keep the bit pattern of DWORDs above Int32.MaxValue.
        "DWord"       { [BitConverter]::ToInt32([BitConverter]::GetBytes([int64]$Entry.Value), 0) }
        "QWord"       { [int64]$Entry.Value }
        "Binary"      { [byte[]]@($Entry.Value) }
        "MultiString" { [string[]]@($Entry.Value) }
        default       { [string]$Entry.Value }
    }
    $subKey = $Entry.Path -replace '^HKLM:\\', ''
    $key = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($subKey)
    try { $key.SetValue($Entry.Name, $value, $kind) }
    finally { $key.Close() }
    Write-Host "Restored: $($Entry.Name) = $($Entry.Value)"
}

if ($original) {
    foreach ($entry in $original) { Restore-Value $entry }
}
else {
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
    if (Test-Path $RegPath) {
        foreach ($Name in $ValuesToRemove) { Remove-ValueIfPresent $RegPath $Name }
    }
    if (Test-Path $AUSubkey) { Remove-ValueIfPresent $AUSubkey "AUPowerManagement" }
    if (Test-Path $UXRegPath) {
        foreach ($Name in "ActiveHoursEnd", "ActiveHoursStart", "AllowMUUpdateService",
                          "SmartActiveHoursState", "UserChoiceActiveHoursStart", "UserChoiceActiveHoursEnd") {
            Remove-ValueIfPresent $UXRegPath $Name
        }
    }
}

# Older KiWin versions blocked drivers; that value was never in the snapshot.
if (Test-Path $RegPath) {
    $drivers = Get-ItemProperty -Path $RegPath -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue
    if ($original -and $drivers -and $drivers.ExcludeWUDriversInQualityUpdate -eq 1) {
        Remove-ValueIfPresent $RegPath "ExcludeWUDriversInQualityUpdate"
    }
}

foreach ($keyPath in $AUSubkey, $RegPath) {
    $key = Get-Item -LiteralPath $keyPath -ErrorAction SilentlyContinue
    if ($key -and -not $key.GetValueNames() -and -not $key.GetSubKeyNames()) {
        Remove-Item -LiteralPath $keyPath -Force -Recurse
        Write-Host "Removed empty key: $keyPath"
    }
}

$HelperFolders = @(
    $StateFolder,
    "C:\ProgramData\Windows Updates Settings",
    "C:\ProgramData\UpdateWindowsUpdatePoliciesAnnually"
)
foreach ($HelperFolder in $HelperFolders) {
    if (Test-Path $HelperFolder) {
        Remove-Item -Path $HelperFolder -Recurse -Force
        Write-Host "Removed helper folder: $HelperFolder"
    }
}
$kiwinData = "C:\ProgramData\KiWin"
if ((Test-Path $kiwinData) -and -not (Get-ChildItem -LiteralPath $kiwinData -Force)) {
    Remove-Item -LiteralPath $kiwinData -Force
}

Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue

Write-Host "`nUpdate policy removed. Windows Update is back to its previous settings."
