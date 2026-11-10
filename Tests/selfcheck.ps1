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

# WinUtil's update function is copied into its own script; a fake WinUtil proves it runs, without touching the system.
. ([scriptblock]::Create((Import-Part 'KiWin.ps1' 'New-WinUtilUpdatesScript') -join "`n"))
$fake = Join-Path $tmp 'winutil.ps1'
$out = Join-Path $tmp 'updates.ps1'
$marker = Join-Path $tmp 'ran.txt'
Set-Content -LiteralPath $fake -Value "function Other { }`nfunction Invoke-WPFUpdatessecurity { Write-WinUtilLog -Message x; Set-Content -LiteralPath '$marker' -Value ok }"
Assert (New-WinUtilUpdatesScript $fake $out) 'update function is found in WinUtil'
$null = Invoke-ChildScript $out
Assert (Test-Path -LiteralPath $marker) 'generated script runs the function, with Write-WinUtilLog stubbed'
Set-Content -LiteralPath $fake -Value 'function Other { }'
Assert (-not (New-WinUtilUpdatesScript $fake $out)) 'a WinUtil without the function is reported'
Remove-Item -LiteralPath $tmp -Recurse -Force

Write-Host 'All checks passed.'
