# Removes the Windows Update policy that older KiWin versions set (they pinned the
# feature release, blocked drivers and .NET/Office updates), its re-apply task,
# and its helper files. The values go back to Windows defaults.

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # throw, not exit: run through irm | iex, exit would close the user's window.
    throw "Administrator rights required. Open PowerShell as administrator and run this again."
}

$StateFolder  = "C:\ProgramData\KiWin\UpdatePolicy"
$Wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$Ux = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

$UndoNames = @{
    $Wu      = "ProductVersion", "TargetReleaseVersion", "TargetReleaseVersionInfo", "DeferQualityUpdates",
               "DeferQualityUpdatesPeriodInDays", "ExcludeUpdateClassifications", "ExcludeWUDriversInQualityUpdate", "AUOptions"
    "$Wu\AU" = @("AUPowerManagement")
    $Ux      = "ActiveHoursStart", "ActiveHoursEnd", "AllowMUUpdateService", "SmartActiveHoursState",
               "UserChoiceActiveHoursStart", "UserChoiceActiveHoursEnd"
}

# The other names are DTLegit's tasks, which older KiWin versions used.
$Tasks = "KiWinUpdatePolicyRenewal", "WindowsUpdateSettingsTask", "CheckSecuritySettings", "ReapplySecuritySettings"

# Only undo when KiWin really applied its policy (its timestamp or a task); otherwise
# these values belong to Windows or another tool. A bare folder is not proof.
if (-not (Test-Path -LiteralPath (Join-Path $StateFolder "LastApplied.txt")) -and
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

foreach ($path in $UndoNames.Keys) {
    foreach ($name in $UndoNames[$path]) {
        Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    }
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
Write-Host "`nUpdate policy removed. Windows Update is back to its defaults."
