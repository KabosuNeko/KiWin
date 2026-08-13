# Update Policy Changer
# filename: update_policy_changer.ps1
#
# Limits Windows Home to security updates for 365 days, blocking feature updates.
# Prevents unwanted system changes and re-installed bloatware.
# Note: For Windows Pro or above, use the Pro variant for a permanent fix.
# Special thanks to DTLegit.

# Define the registry path
$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# Pin to the currently installed Windows version so the policy never goes stale
# (e.g. machine on 25H2 is pinned to 25H2, blocking newer feature updates).
try {
    $CurrentVersion = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion")
    $TargetVersion = $CurrentVersion.DisplayVersion
    if (-not $TargetVersion) { $TargetVersion = "24H2" }
}
catch {
    $TargetVersion = "24H2"
}

# Define the registry values
$RegistrySettings = @{
    "DeferQualityUpdates"              = 1
    "DeferQualityUpdatesPeriodInDays"  = 4
    "ProductVersion"                   = "Windows 11"
    "TargetReleaseVersion"             = 1
    "TargetReleaseVersionInfo"         = $TargetVersion
}

# Ensure the registry path exists
if (-not (Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}

# Set the registry values
foreach ($Name in $RegistrySettings.Keys) {
    $Value = $RegistrySettings[$Name]

    # Determine the value type (DWORD or String)
    $Type = if ($Value -is [int]) { "DWord" } else { "String" }

    # Set the registry value
    Set-ItemProperty -Path $RegPath -Name $Name -Value $Value -Type $Type -Force
    Write-Host "Set $Name to $Value ($Type)"
}

Write-Host "`nRegistry settings applied successfully. Pinned to Windows $TargetVersion."