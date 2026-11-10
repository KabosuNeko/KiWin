# Reverts WinUtil's "Razer Software Auto-Install - Disable" tweak, which
# KiWin applied up to v1.1.4 and the first standalone script. Besides Razer
# software, it turned off automatic driver downloads for every device and
# disabled driver co-installers.

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator rights required." -ForegroundColor Red
    exit 1
}

$driverSearching = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"
if (-not (Test-Path $driverSearching)) { New-Item -Path $driverSearching -Force | Out-Null }
# 1 is the Windows default: download drivers from Windows Update automatically.
New-ItemProperty -Path $driverSearching -Name "SearchOrderConfig" -Value 1 -PropertyType DWord -Force | Out-Null
Write-Host "Automatic driver downloads: on"

$deviceInstaller = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer"
if (Get-ItemProperty -Path $deviceInstaller -Name "DisableCoInstallers" -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $deviceInstaller -Name "DisableCoInstallers" -Force
    Write-Host "Driver co-installers: on"
}

$razerPath = Join-Path $env:SystemRoot "Installer\Razer"
if (Test-Path -LiteralPath $razerPath) {
    & icacls.exe $razerPath /remove:d "*S-1-1-0" | Out-Null
    if (-not (Get-ChildItem -LiteralPath $razerPath -Force)) {
        Remove-Item -LiteralPath $razerPath -Force
    }
    Write-Host "Razer installer folder unlocked"
}

Write-Host "Done."
