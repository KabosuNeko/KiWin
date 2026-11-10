# Creates a restore point before debloating, bypassing the 24h throttle.
# Exit code 0: created. Exit code 2: not created; KiWin then asks before going on.
# Win11Debloat also backs up the registry keys it changes on its own.

$ErrorActionPreference = 'Continue'

$srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
$hadFreq = $false
$oldFreq = $null
try {
    $p = Get-ItemProperty -LiteralPath $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue
    if ($null -ne $p) {
        $hadFreq = $true
        $oldFreq = $p.SystemRestorePointCreationFrequency
    }
}
catch { }

$ok = $false
try {
    # RPSessionInterval is 1 while System Protection is on for at least one drive.
    $sr = Get-ItemProperty -LiteralPath $srKey -ErrorAction SilentlyContinue
    if (-not $sr -or $sr.RPSessionInterval -ne 1) {
        Write-Host "System Protection is off; turning it on for $env:SystemDrive (it reserves some disk space)."
    }
    try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop }
    catch { Write-Host "Enable-ComputerRestore: $($_.Exception.Message)" }

    if (-not (Test-Path -LiteralPath $srKey)) { New-Item -Path $srKey -Force | Out-Null }
    New-ItemProperty -LiteralPath $srKey -Name SystemRestorePointCreationFrequency -Value 0 -PropertyType DWord -Force | Out-Null

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
            New-ItemProperty -LiteralPath $srKey -Name SystemRestorePointCreationFrequency -Value $oldFreq -PropertyType DWord -Force | Out-Null
        }
        else {
            Remove-ItemProperty -LiteralPath $srKey -Name SystemRestorePointCreationFrequency -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

if ($ok) { exit 0 }
exit 2
