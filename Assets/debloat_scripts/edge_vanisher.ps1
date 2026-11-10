# Removes Edge from Windows 11 and blocks reinstall; WebView2 and every user's
# Edge profile (%LOCALAPPDATA%\Microsoft\Edge\User Data) are kept.
# shortcut: only the x86 system install and the running account's per-user install are removed, loop over profiles if per-user Edge shows up for others.
# EdgeUpdate stays because WebView2 updates through it; its attempts to put
# Edge back fail on the locked folder below.
# To allow Edge again, delete the locked folder from an elevated prompt first:
#   takeown /F "%ProgramFiles(x86)%\Microsoft\Edge" /R /D Y
#   icacls "%ProgramFiles(x86)%\Microsoft\Edge" /reset /T /C
#   rmdir /S /Q "%ProgramFiles(x86)%\Microsoft\Edge"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator rights required." -ForegroundColor Red
    exit 1
}

$administratorsSid = "*S-1-5-32-544"

function Remove-ShortcutByTarget {
    param(
        [string[]]$SearchRoots,
        [string[]]$TargetPatterns
    )

    $wshShell = $null
    try {
        $wshShell = New-Object -ComObject WScript.Shell
    }
    catch {
        return
    }

    foreach ($root in $SearchRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        Get-ChildItem -LiteralPath $root -Filter *.lnk -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $shortcut = $wshShell.CreateShortcut($_.FullName)
                $targetData = @(
                    $shortcut.TargetPath,
                    $shortcut.Arguments,
                    $shortcut.IconLocation,
                    $_.BaseName
                ) -join ' '

                foreach ($pattern in $TargetPatterns) {
                    if ($targetData -like $pattern) {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                        break
                    }
                }
            }
            catch {}
        }
    }
}

# setup.exe sits in Application\<version>\Installer; take the newest version.
function Get-EdgeInstaller {
    param([string]$ApplicationDir)
    Get-ChildItem -Path "$ApplicationDir\*\Installer\setup.exe" -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]$_.Directory.Parent.Name } catch { [version]'0.0' } } -Descending |
        Select-Object -First 1
}

function Invoke-EdgeUninstaller {
    param([System.IO.FileInfo]$Installer, [switch]$SystemLevel)
    $arguments = "--uninstall --force-uninstall --verbose-logging"
    if ($SystemLevel) { $arguments += " --system-level" }
    $proc = Start-Process $Installer.FullName -ArgumentList $arguments -Wait -PassThru
    # 19 is Chromium's UNINSTALL_SUCCESSFUL.
    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 19) {
        Write-Host "Edge uninstaller finished (code $($proc.ExitCode))."
        return $true
    }
    Write-Warning "Edge uninstaller exited with code $($proc.ExitCode)."
    return $false
}

# Only the browser itself; msedgewebview2 belongs to WebView2 and must keep running.
Stop-Process -Name msedge -Force -ErrorAction SilentlyContinue

$systemInstaller = Get-EdgeInstaller "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
$userInstaller = Get-EdgeInstaller "$env:LOCALAPPDATA\Microsoft\Edge\Application"

if ($systemInstaller -or $userInstaller) {
    # Outside the EEA the uninstaller refuses unless the legacy Edge stub exists.
    $legacyStub = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe"
    $createdStub = $false
    if (-not (Test-Path -LiteralPath $legacyStub)) {
        try {
            New-Item -ItemType File -Path $legacyStub -Force -ErrorAction Stop | Out-Null
            $createdStub = $true
        }
        catch { Write-Host "Could not create the legacy Edge stub: $($_.Exception.Message)" }
    }

    if ($systemInstaller -and -not (Invoke-EdgeUninstaller $systemInstaller -SystemLevel)) {
        Write-Host "Removing the Edge files directly."
    }
    if ($userInstaller) {
        $null = Invoke-EdgeUninstaller $userInstaller
    }

    if ($createdStub) { Remove-Item -LiteralPath $legacyStub -Force -ErrorAction SilentlyContinue }
}

Stop-Process -Name msedge -Force -ErrorAction SilentlyContinue

$pathsToRemove = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge",
    "${env:ProgramFiles(x86)}\Microsoft\EdgeCore",
    # Per-user binaries only; User Data next to it is the profile and stays.
    "$env:LOCALAPPDATA\Microsoft\Edge\Application"
)

foreach ($path in $pathsToRemove) {
    if (Test-Path -LiteralPath $path) {
        takeown /F $path /R /D Y | Out-Null
        icacls $path /grant "${administratorsSid}:F" /T /C | Out-Null
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Shortcuts in every local profile, not just the account running KiWin.
$profileRoots = @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
    Where-Object { -not $_.Special -and $_.LocalPath } |
    Select-Object -ExpandProperty LocalPath)
$defaultProfile = [Environment]::ExpandEnvironmentVariables(
    (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue).Default)
if ($defaultProfile) { $profileRoots += $defaultProfile }

$searchRoots = @(
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
    "$env:PUBLIC\Desktop",
    [Environment]::GetFolderPath('Desktop')
)
foreach ($root in $profileRoots) {
    $searchRoots += Join-Path $root "Desktop"
    $searchRoots += Join-Path $root "AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
    $searchRoots += Join-Path $root "AppData\Roaming\Microsoft\Internet Explorer\Quick Launch"
}

Remove-ShortcutByTarget -SearchRoots ($searchRoots | Select-Object -Unique) -TargetPatterns @(
    "*msedge.exe*",
    "*Microsoft Edge*"
)

$regKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe",
    "HKLM:\SOFTWARE\Microsoft\Edge",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Edge",
    # Left behind when the uninstaller refused and the files were deleted directly.
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
)

foreach ($key in $regKeys) {
    if (Test-Path -LiteralPath $key) {
        Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$protectBase = "${env:ProgramFiles(x86)}\Microsoft\Edge"
$protectApp  = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"

New-Item -ItemType Directory -Path $protectBase -Force | Out-Null
New-Item -ItemType Directory -Path $protectApp -Force | Out-Null

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetOwner([System.Security.Principal.NTAccount]$currentUser)
$acl.SetAccessRuleProtection($true, $false)

$allowRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $currentUser,
    "FullControl,TakeOwnership,ChangePermissions",
    "ContainerInherit,ObjectInherit",
    "None",
    "Allow"
)

$denySids = @(
    "S-1-5-18",
    "S-1-5-32-544",
    "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464"
)

$acl.AddAccessRule($allowRule)

foreach ($sid in $denySids) {
    $acl.AddAccessRule(
        (New-Object System.Security.AccessControl.FileSystemAccessRule(
            (New-Object System.Security.Principal.SecurityIdentifier($sid)),
            "TakeOwnership,ChangePermissions",
            "ContainerInherit,ObjectInherit",
            "None",
            "Deny"
        ))
    )
}

Set-Acl -Path $protectBase -AclObject $acl

Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Process explorer
