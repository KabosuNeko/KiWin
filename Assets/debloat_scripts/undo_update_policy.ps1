# Removes the policy set by update_policy_changer.ps1, its renewal task, and its
# helper files, then puts back any values saved in Original.json from before KiWin.

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # throw, not exit: run through irm | iex, exit would close the user's window.
    throw "Administrator rights required. Open PowerShell as administrator and run this again."
}

$StateFolder  = "C:\ProgramData\KiWin\UpdatePolicy"
$OriginalFile = Join-Path $StateFolder "Original.json"
$Wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$Ux = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

# Same list as $UndoNames in update_policy_changer.ps1.
$UndoNames = @{
    $Wu      = "ProductVersion", "TargetReleaseVersion", "TargetReleaseVersionInfo", "DeferQualityUpdates",
               "DeferQualityUpdatesPeriodInDays", "ExcludeUpdateClassifications", "ExcludeWUDriversInQualityUpdate", "AUOptions"
    "$Wu\AU" = @("AUPowerManagement")
    $Ux      = "ActiveHoursStart", "ActiveHoursEnd", "AllowMUUpdateService", "SmartActiveHoursState",
               "UserChoiceActiveHoursStart", "UserChoiceActiveHoursEnd"
}

# The other names are DTLegit's tasks, which older KiWin versions used.
$Tasks = "KiWinUpdatePolicyRenewal", "WindowsUpdateSettingsTask", "CheckSecuritySettings", "ReapplySecuritySettings"

# Only undo when KiWin really applied its policy (saved originals, the old timestamp, or a task).
# A bare state folder is not proof: a failed install creates it before changing anything.
if (-not (Test-Path -LiteralPath $OriginalFile) -and
    -not (Test-Path -LiteralPath (Join-Path $StateFolder "LastApplied.txt")) -and
    -not (Get-ScheduledTask -TaskName $Tasks -ErrorAction SilentlyContinue)) {
    Write-Host "KiWin's update policy is not installed; nothing to undo."
    return
}

# Stop the renewal first so it cannot re-apply the policy halfway through.
foreach ($task in $Tasks) {
    if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $task -Confirm:$false
        Write-Host "Removed scheduled task: $task"
    }
}

# Read before the folder is deleted. Not wrapped in @(): on PowerShell 5.1 that
# turns a JSON array into a single element.
$original = if (Test-Path -LiteralPath $OriginalFile) { Get-Content -LiteralPath $OriginalFile -Raw | ConvertFrom-Json }

foreach ($path in $UndoNames.Keys) {
    foreach ($name in $UndoNames[$path]) {
        Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    }
}

foreach ($entry in $original) {
    if (-not (Test-Path $entry.Path)) { New-Item -Path $entry.Path -Force | Out-Null }
    New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $entry.Kind -Force | Out-Null
    Write-Host "Restored: $($entry.Name) = $($entry.Value)"
}

foreach ($keyPath in "$Wu\AU", $Wu) {
    $key = Get-Item -LiteralPath $keyPath -ErrorAction SilentlyContinue
    if ($key -and -not $key.GetValueNames() -and -not $key.GetSubKeyNames()) {
        Remove-Item -LiteralPath $keyPath -Force
    }
}

# rmdir, not Remove-Item: users can plant junctions under ProgramData, and 5.1's Remove-Item -Recurse follows them.
foreach ($folder in $StateFolder, "C:\ProgramData\Windows Updates Settings", "C:\ProgramData\UpdateWindowsUpdatePoliciesAnnually") {
    if (Test-Path -LiteralPath $folder) {
        cmd /c rmdir /s /q "$folder"
        Write-Host "Removed helper folder: $folder"
    }
}
if ((Test-Path "C:\ProgramData\KiWin") -and -not (Get-ChildItem "C:\ProgramData\KiWin" -Force)) {
    Remove-Item "C:\ProgramData\KiWin" -Force
}

Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Write-Host "`nUpdate policy removed. Windows Update is back to its previous settings."
