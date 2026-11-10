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

# shortcut: hand-kept dates (Home/Pro, Enterprise/Education), add each new release when Microsoft publishes its lifecycle; unlisted releases count as supported.
$EndOfServicing = @{
    "21H2" = "2023-10-10", "2024-10-08"
    "22H2" = "2024-10-08", "2025-10-14"
    "23H2" = "2025-11-11", "2026-11-10"
    "24H2" = "2026-10-13", "2027-10-12"
    "25H2" = "2027-10-12", "2028-10-10"
}

# Everything undo_update_policy.ps1 removes; keep the two lists in sync.
$UndoNames = @{
    $Wu      = "ProductVersion", "TargetReleaseVersion", "TargetReleaseVersionInfo", "DeferQualityUpdates",
               "DeferQualityUpdatesPeriodInDays", "ExcludeUpdateClassifications", "ExcludeWUDriversInQualityUpdate", "AUOptions"
    "$Wu\AU" = @("AUPowerManagement")
    $Ux      = "ActiveHoursStart", "ActiveHoursEnd", "AllowMUUpdateService", "SmartActiveHoursState",
               "UserChoiceActiveHoursStart", "UserChoiceActiveHoursEnd"
}

function Get-EndOfServicing([string]$Release, [string]$Edition) {
    if (-not $EndOfServicing.ContainsKey($Release)) { return $null }
    [datetime]$EndOfServicing[$Release][[int]($Edition -match "Enterprise|Education")]
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
    Set-Value $Ux "AllowMUUpdateService" 0
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
    # That version also blocked drivers from Windows Update.
    Remove-ItemProperty -Path $Wu -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue
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
