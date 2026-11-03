# Clears taskbar and Start pins for the current user and the Default profile.

# The shell owns the layout and writes it back on exit, so stop it first.
Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

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

# Deleting start2.bin does not work: Start regenerates the default pins.
# An empty layout clears the pinned area instead.
# shortcut: the blank layout is build-specific; re-capture it if Start resets to default pins.
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

Start-Sleep -Seconds 1
Start-Process explorer -ErrorAction SilentlyContinue

Write-Host "Taskbar and Start pinned items removed."
