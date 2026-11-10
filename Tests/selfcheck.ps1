# Checks the non-trivial logic without changing the system. No admin needed.
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Tests\selfcheck.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

# Load named functions and assignments from a script without running it.
function Import-Part([string]$File, [string[]]$Names) {
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $File), [ref]$null, [ref]$null)
    $ast.FindAll({ param($n)
        ($n -is [Management.Automation.Language.FunctionDefinitionAst] -and $Names -contains $n.Name) -or
        ($n -is [Management.Automation.Language.AssignmentStatementAst] -and $Names -contains $n.Left.Extent.Text)
    }, $true) | ForEach-Object { $_.Extent.Text }
}
function Assert($Condition, [string]$What) { if (-not $Condition) { throw "FAIL: $What" }; Write-Host "ok  $What" }

. ([scriptblock]::Create((Import-Part 'Assets\debloat_scripts\update_policy_changer.ps1' 'Get-EndOfServicing') -join "`n"))
# Real dates: 24H2 Home/Pro 2026-10-13, Enterprise 2027-10-12, 23H2 Home/Pro 2025-11-11. The formula must never be later.
Assert ((Get-EndOfServicing '24H2' 'Professional') -eq [datetime]'2026-10-01') '24H2 Pro end of servicing'
Assert ((Get-EndOfServicing '24H2' 'Enterprise') -eq [datetime]'2027-10-01') '24H2 Enterprise end of servicing'
Assert ((Get-EndOfServicing '23H2' 'Core') -le [datetime]'2025-11-11') '23H2 Home is not later than the real date'
Assert ((Get-EndOfServicing '26H2' 'Professional') -eq [datetime]'2028-10-01') 'future release gets a date too'
Assert ($null -eq (Get-EndOfServicing '' 'Professional')) 'missing release gives no date'

# Original.json written the way the changer writes it, read by the undo's own line.
# PowerShell 5.1 must give back every entry, also for one.
$readOriginal = [scriptblock]::Create((Import-Part 'Assets\debloat_scripts\undo_update_policy.ps1' '$original') -join "`n")
foreach ($count in 1, 3) {
    $saved = 1..$count | ForEach-Object { [pscustomobject]@{ Path = 'HKLM:\X'; Name = "V$_"; Value = $_; Kind = 'DWord' } }
    $OriginalFile = [IO.Path]::GetTempFileName()
    ConvertTo-Json -InputObject @($saved) | Set-Content -LiteralPath $OriginalFile -Encoding UTF8
    . $readOriginal
    $n = 0
    foreach ($entry in $original) { $n++; Assert ($entry.Name -eq "V$n" -and $entry.Kind -eq 'DWord') "entry $n of $count keeps its fields" }
    Assert ($n -eq $count) "Original.json round trip with $count entries"
    Remove-Item -LiteralPath $OriginalFile
}

# The two scripts run standalone, so each carries the list; they must match.
$lists = 'update_policy_changer.ps1', 'undo_update_policy.ps1' | ForEach-Object {
    (Import-Part "Assets\debloat_scripts\$_" '$UndoNames') -replace '\s+', ' '
}
Assert ($lists[0] -and $lists[0] -eq $lists[1]) '$UndoNames is the same in the changer and the undo'

Assert ('6830bf501d2740c3317133ac0ecdc2a3ab80ed7f6c83e7f0f20dc66afbf758a7 *Win11Debloat.zip' -match
    '^([0-9a-fA-F]{64})\s+\*?Win11Debloat\.zip\s*$') 'SHA256SUMS line is recognized'

. ([scriptblock]::Create((Import-Part 'KiWin.ps1' 'Invoke-ChildScript') -join "`n"))
$tmp = Join-Path ([IO.Path]::GetTempPath()) 'kiwin selfcheck'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$child = Join-Path $tmp 'child.ps1'
Set-Content -LiteralPath $child -Value 'param([string]$A) if ($A -ne "C:\a b\c.json") { exit 9 }; exit ([int]$env:KIWIN_CODE)'
$env:KIWIN_CODE = 0; Assert ((Invoke-ChildScript $child @('-A', 'C:\a b\c.json')) -eq 0) 'child gets a path with spaces intact'
$env:KIWIN_CODE = 2; Assert ((Invoke-ChildScript $child @('-A', 'C:\a b\c.json') -OkCodes 0, 2) -eq 2) 'allowed nonzero exit code is returned'
$env:KIWIN_CODE = 5; $threw = $false; try { Invoke-ChildScript $child @('-A', 'C:\a b\c.json') } catch { $threw = $true }
Assert $threw 'unexpected exit code throws'
Remove-Item -LiteralPath $tmp -Recurse -Force

Write-Host 'All checks passed.'
