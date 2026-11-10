# Keeps Windows on the installed feature release and delays cumulative updates
# by 4 days. Not "security only": cumulative updates carry non-security fixes too.
# A SYSTEM task re-runs this at startup and weekly: it drops the pin 60 days
# before end of servicing, and pins the new release after a feature update.
# Values that existed before KiWin go to Original.json for undo_update_policy.ps1.
# Original implementation; the deferral technique follows DTLegit's FullWinUpdate-Disabler.

param([switch]$Renewal)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator rights required." -ForegroundColor Red
    exit 1
}

$TaskName     = "KiWinUpdatePolicyRenewal"
$StateFolder  = "C:\ProgramData\KiWin\UpdatePolicy"
$OriginalFile = Join-Path $StateFolder "Original.json"
$Wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$Ux = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

# Everything undo_update_policy.ps1 removes; keep the two lists in sync.
$UndoNames = @{
    $Wu      = "ProductVersion", "TargetReleaseVersion", "TargetReleaseVersionInfo", "DeferQualityUpdates",
               "DeferQualityUpdatesPeriodInDays", "ExcludeUpdateClassifications", "ExcludeWUDriversInQualityUpdate", "AUOptions"
    "$Wu\AU" = @("AUPowerManagement")
    $Ux      = "ActiveHoursStart", "ActiveHoursEnd", "AllowMUUpdateService", "SmartActiveHoursState",
               "UserChoiceActiveHoursStart", "UserChoiceActiveHoursEnd"
}

# Computed, not listed, so the copy the renewal task runs also knows future releases.
# Windows 11 releases end in October two years later (three for Enterprise/Education);
# October 1 errs early (23H2 Home/Pro actually ran to November 11).
function Get-EndOfServicing([string]$Release, [string]$Edition) {
    if ($Release -notmatch "^\d{2}H\d$") { return $null }
    $years = 2 + [int]($Edition -match "Enterprise|Education")
    [datetime]("20{0}-10-01" -f ([int]$Release.Substring(0, 2) + $years))
}

function Set-Value([string]$Path, [string]$Name, $Value, [string]$Type = "DWord") {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Set-KiWinUpdatePolicy {
    $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $release = $cv.DisplayVersion
    $eos = Get-EndOfServicing $release $cv.EditionID

    if ($release -notmatch "^\d{2}H\d$") {
        Write-Warning "Could not detect the feature release; feature updates are not pinned."
        $release = $null
    }
    elseif ($eos -and (Get-Date) -ge $eos.AddDays(-60)) {
        Write-Warning ("Windows 11 {0} reaches end of servicing on {1:yyyy-MM-dd}; not pinned, so Windows can upgrade." -f $release, $eos)
        $release = $null
    }

    if ($release) {
        Set-Value $Wu "ProductVersion" "Windows 11" "String"
        Set-Value $Wu "TargetReleaseVersion" 1
        Set-Value $Wu "TargetReleaseVersionInfo" $release "String"
        Write-Host "Pinned to Windows 11 $release."
    }
    else {
        foreach ($name in "ProductVersion", "TargetReleaseVersion", "TargetReleaseVersionInfo") {
            Remove-ItemProperty -Path $Wu -Name $name -ErrorAction SilentlyContinue
        }
    }

    Set-Value $Wu "DeferQualityUpdates" 1
    Set-Value $Wu "DeferQualityUpdatesPeriodInDays" 4
    Set-Value "$Wu\AU" "AUPowerManagement" 0
    Set-Value $Ux "ActiveHoursStart" 8
    Set-Value $Ux "ActiveHoursEnd" 2
    Set-Value $Ux "SmartActiveHoursState" 0
    Set-Value $Ux "UserChoiceActiveHoursStart" 8
    Set-Value $Ux "UserChoiceActiveHoursEnd" 2
}

if ($Renewal) {
    Set-KiWinUpdatePolicy
    exit 0
}

# The renewal task runs a script from here as SYSTEM, and standard users can
# create folders under ProgramData: take ownership and reset the ACL before use.
function Protect-Folder([string]$Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    if ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "$Path is a link, not a folder."
    }
    # /L acts on links themselves, so a planted junction inside cannot redirect the change.
    & icacls.exe $Path /setowner "*S-1-5-32-544" /T /C /L /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls /setowner failed on $Path (code $LASTEXITCODE)" }
    & icacls.exe $Path /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" /T /C /L /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls /grant failed on $Path (code $LASTEXITCODE)" }
}

try {
    Protect-Folder (Split-Path $StateFolder -Parent)
    Protect-Folder $StateFolder
}
catch {
    Write-Host "Could not secure ${StateFolder}: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# An older KiWin left its own values in place, so they are not the originals.
# The DTLegit task names come from KiWin versions before the rewrite in 3911e73.
$legacy = -not (Test-Path $OriginalFile) -and
    ((Test-Path (Join-Path $StateFolder "LastApplied.txt")) -or
     (Get-ScheduledTask -TaskName $TaskName, "WindowsUpdateSettingsTask", "CheckSecuritySettings", "ReapplySecuritySettings" -ErrorAction SilentlyContinue))

if ($legacy) {
    Write-Host "Earlier KiWin install found: undo will reset these values to Windows defaults."
    # Those versions also blocked drivers, and .NET/Office updates (Microsoft Update).
    Remove-ItemProperty -Path $Wu -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $Ux -Name "AllowMUUpdateService" -ErrorAction SilentlyContinue
    # DTLegit's task re-applies its whole policy (driver block included) at every startup.
    foreach ($t in "WindowsUpdateSettingsTask", "CheckSecuritySettings", "ReapplySecuritySettings") {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
    }
    # rmdir, not Remove-Item: users can plant junctions under ProgramData, and 5.1's Remove-Item -Recurse follows them.
    foreach ($d in "C:\ProgramData\Windows Updates Settings", "C:\ProgramData\UpdateWindowsUpdatePoliciesAnnually") {
        if (Test-Path -LiteralPath $d) { cmd /c rmdir /s /q "$d" }
    }
}
elseif (-not (Test-Path $OriginalFile)) {
    $saved = foreach ($path in $UndoNames.Keys) {
        $key = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        foreach ($name in $UndoNames[$path]) {
            if ($key -and $key.GetValueNames() -contains $name) {
                [pscustomobject]@{ Path = $path; Name = $name; Value = $key.GetValue($name); Kind = [string]$key.GetValueKind($name) }
            }
        }
    }
    ConvertTo-Json -InputObject @($saved) | Set-Content -LiteralPath $OriginalFile -Encoding UTF8
}

Set-KiWinUpdatePolicy
Remove-Item -LiteralPath (Join-Path $StateFolder "LastApplied.txt") -Force -ErrorAction SilentlyContinue

# The task runs a stable copy so it survives cleanup of the downloaded script.
$renewalScript = Join-Path $StateFolder "update_policy_changer.ps1"
Copy-Item -Path $PSCommandPath -Destination $renewalScript -Force

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$renewalScript`" -Renewal"
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -DisallowStartIfOnBatteries:$false -RestartCount 5 -RestartInterval "PT1M"
Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force `
    -Trigger @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "03:00AM")) `
    -Description "KiWin: keep the Windows Update policy in line with the installed release and its end of servicing." | Out-Null
Write-Host "Renewal task '$TaskName' registered."
Write-Host "Done. Cumulative updates arrive 4 days late; feature upgrades wait until near end of servicing."
