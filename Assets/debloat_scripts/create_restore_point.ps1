# KiWin: create a System Restore point before debloating.
#
# Windows throttles restore points to one per 24h. This script temporarily sets
# SystemRestorePointCreationFrequency to 0, creates the point, then restores the
# previous value. If the restore point still fails, it exports HKLM and HKCU as a
# fallback so changes can be reviewed/reverted.
#
# Always exits 0 (best effort); the outcome is written to stdout and the KiWin log.

$ErrorActionPreference = 'Continue'

$freqKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
$hadFreq = $false
$oldFreq = $null
try {
    $p = Get-ItemProperty -LiteralPath $freqKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue
    if ($null -ne $p) {
        $hadFreq = $true
        $oldFreq = $p.SystemRestorePointCreationFrequency
    }
}
catch { }

$ok = $false
try {
    try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop }
    catch { Write-Host "Enable-ComputerRestore: $($_.Exception.Message)" }

    if (-not (Test-Path -LiteralPath $freqKey)) { New-Item -Path $freqKey -Force | Out-Null }
    New-ItemProperty -LiteralPath $freqKey -Name SystemRestorePointCreationFrequency -Value 0 -PropertyType DWord -Force | Out-Null

    Checkpoint-Computer -Description 'KiWin: before debloat' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    Write-Host 'Restore point created.'
    $ok = $true
}
catch {
    Write-Host "Restore point failed: $($_.Exception.Message)"
}
finally {
    try {
        if ($hadFreq) {
            New-ItemProperty -LiteralPath $freqKey -Name SystemRestorePointCreationFrequency -Value $oldFreq -PropertyType DWord -Force | Out-Null
        }
        else {
            Remove-ItemProperty -LiteralPath $freqKey -Name SystemRestorePointCreationFrequency -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

if (-not $ok) {
    $backupDir = Join-Path $env:LOCALAPPDATA ('KiWin\RegBackup-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try {
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        & reg.exe export HKLM (Join-Path $backupDir 'HKLM.reg') /y | Out-Null
        & reg.exe export HKCU (Join-Path $backupDir 'HKCU.reg') /y | Out-Null
        Write-Host "Registry fallback exported to $backupDir"
    }
    catch {
        Write-Host "Fallback registry export failed: $($_.Exception.Message)"
    }
}

exit 0
