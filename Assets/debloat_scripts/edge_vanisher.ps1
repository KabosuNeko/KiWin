# Edge Vanisher
# filename: edge_vanisher.ps1
#
# This script's purpose is to remove Edge from Windows 11 systems and prevent the system from reinstalling it.
# The user can still reinstall Edge by downloading it from Microsoft's website. Preserves msedgewebview2.


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
		if (-not (Test-Path $root)) {
			continue
		}

		Get-ChildItem -Path $root -Filter *.lnk -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
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
						Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
						break
					}
				}
			}
			catch {}
		}
	}
}

$edgeInstaller = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($edgeInstaller) {
	Start-Process $edgeInstaller.FullName -ArgumentList "--uninstall --system-level --force-uninstall --verbose-logging" -Wait
}

Get-Process | Where-Object { $_.Name -like "*edge*" } | Stop-Process -Force -ErrorAction SilentlyContinue

$pathsToRemove = @(
	"$env:LOCALAPPDATA\Microsoft\Edge",
	"${env:ProgramFiles(x86)}\Microsoft\Edge",
	"${env:ProgramFiles(x86)}\Microsoft\EdgeCore"
)

foreach ($path in $pathsToRemove) {
	if (Test-Path $path) {
		takeown /F $path /R /D Y | Out-Null
		icacls $path /grant "${administratorsSid}:F" /T /C | Out-Null
		Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
	}
}

Remove-ShortcutByTarget -SearchRoots @(
	"$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
	"$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
	"$env:PUBLIC\Desktop",
	[Environment]::GetFolderPath('Desktop')
) -TargetPatterns @(
	"*msedge.exe*",
	"*Microsoft Edge*"
)

$regKeys = @(
	"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe",
	"HKLM:\SOFTWARE\Microsoft\Edge",
	"HKLM:\SOFTWARE\WOW6432Node\Microsoft\Edge",
	"HKCU:\Software\Microsoft\Edge"
)

foreach ($key in $regKeys) {
	if (Test-Path $key) {
		Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
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
