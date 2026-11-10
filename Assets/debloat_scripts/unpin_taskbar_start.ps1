# Clears taskbar pins for the current user, and Start pins for the current
# user and the Default profile (new accounts). -TaskbarOnly leaves Start alone,
# for runs where Win11Debloat's -ClearStartAllUsers already cleared it.

param(
    [switch]$TaskbarOnly
)

# The shell owns the layout and writes it back on exit, so stop it first.
Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

$quickLaunch = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned"
foreach ($folder in "TaskBar", "ImplicitAppShortcuts") {
    $path = Join-Path $quickLaunch $folder
    if (Test-Path -LiteralPath $path) {
        Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    }
}

$taskband = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
if (Test-Path $taskband) {
    foreach ($name in "Favorites", "FavoritesResolve", "FavoritesChanges", "FavoritesVersion",
                      "FavoritesRemovedChanges", "FavoritesImplicitAppShortcuts") {
        Remove-ItemProperty -Path $taskband -Name $name -Force -ErrorAction SilentlyContinue
    }
}

if (-not $TaskbarOnly) {
    # Deleting start2.bin does not work: Start regenerates the default pins.
    # shortcut: the blank layout is build-specific, re-capture it if Start comes back with default pins.
    $blankTemplate = Join-Path $PSScriptRoot "start2_blank.bin"
    if (Test-Path -LiteralPath $blankTemplate) {
        $relative = "AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin"
        $defaultProfile = [Environment]::ExpandEnvironmentVariables(
            (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList').Default)
        $startLayouts = @(
            "$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin",
            (Join-Path $defaultProfile $relative)
        )

        foreach ($layout in $startLayouts) {
            try {
                $dir = Split-Path $layout -Parent
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                # Keep the first backup only, so a second run does not overwrite the real layout.
                $backup = "$layout.kiwin.bak"
                if ((Test-Path -LiteralPath $layout) -and -not (Test-Path -LiteralPath $backup)) {
                    Copy-Item -LiteralPath $layout -Destination $backup -Force
                }
                Copy-Item -LiteralPath $blankTemplate -Destination $layout -Force
            }
            catch {
                Write-Warning "Could not replace ${layout}: $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Warning "start2_blank.bin is missing; Start pins were not cleared."
    }
}

Start-Sleep -Seconds 1
Start-Process explorer -ErrorAction SilentlyContinue

if ($TaskbarOnly) { Write-Host "Taskbar pinned items removed." }
else { Write-Host "Taskbar and Start pinned items removed." }
