# Unpin Taskbar & Start
# filename: unpin_taskbar_start.ps1
#
# Removes all pinned items from the Taskbar and the Start menu pinned area.

# 1. Stop the shell processes that own the Taskbar/Start state first,
#    otherwise they flush their in-memory layout back to disk on exit.
Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

# 2. Taskbar pins (desktop app shortcuts + taskband registry blob).
$taskbarPins = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
if (Test-Path $taskbarPins) {
	Get-ChildItem -Path $taskbarPins -Force -ErrorAction SilentlyContinue |
		Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}

$taskbarImplicit = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\ImplicitAppShortcuts"
if (Test-Path $taskbarImplicit) {
	Get-ChildItem -Path $taskbarImplicit -Force -Recurse -ErrorAction SilentlyContinue |
		Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}

$taskband = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
if (Test-Path $taskband) {
	Remove-ItemProperty -Path $taskband -Name "Favorites" -Force -ErrorAction SilentlyContinue
	Remove-ItemProperty -Path $taskband -Name "FavoritesResolve" -Force -ErrorAction SilentlyContinue
	Remove-ItemProperty -Path $taskband -Name "FavoritesChanges" -Force -ErrorAction SilentlyContinue
	Remove-ItemProperty -Path $taskband -Name "FavoritesVersion" -Force -ErrorAction SilentlyContinue
	Remove-ItemProperty -Path $taskband -Name "FavoritesRemovedChanges" -Force -ErrorAction SilentlyContinue
	Remove-ItemProperty -Path $taskband -Name "FavoritesImplicitAppShortcuts" -Force -ErrorAction SilentlyContinue
}

# 3. Start menu pins: replace each user's start2.bin with a blank template.
#    Deleting the file does NOT work - the Start menu regenerates it with the
#    default pins. Replacing it with an empty layout clears the pinned area.
$blankTemplate = Join-Path $PSScriptRoot "start2_blank.bin"
if (Test-Path $blankTemplate) {
	$startLayouts = @(
		"$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin",
		"$env:ProgramData\Users\Default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin",
		"C:\Users\Default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin"
	)

	foreach ($layout in $startLayouts) {
		$dir = Split-Path $layout -Parent
		if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null }
		Copy-Item -Path $blankTemplate -Destination $layout -Force -ErrorAction SilentlyContinue
	}
}

$legacyLayouts = @(
	"$env:LOCALAPPDATA\Packages\Microsoft.Windows.Cortana_cw5n1h2txyewy\LocalState\start.bin"
)

foreach ($layout in $legacyLayouts) {
	if (Test-Path $layout) {
		Remove-Item -Path $layout -Force -ErrorAction SilentlyContinue
	}
}

# 4. Remove any leftover LayoutModification.xml we may have written in
#    older versions of this script (blank start2.bin handles the layout now).
$shellLayoutDir = "$env:LOCALAPPDATA\Microsoft\Windows\Shell"
$legacyLayoutXml = Join-Path $shellLayoutDir "LayoutModification.xml"
if (Test-Path $legacyLayoutXml) {
	Remove-Item -Path $legacyLayoutXml -Force -ErrorAction SilentlyContinue
}

# 5. Bring the shell back up.
Start-Sleep -Seconds 1
Start-Process explorer -ErrorAction SilentlyContinue

Write-Host "Taskbar and Start pinned items removed."