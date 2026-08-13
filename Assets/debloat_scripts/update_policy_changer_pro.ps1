# Update Policy Changer Pro
# filename: update_policy_changer_pro.ps1
#
# Limits Windows (Pro+) to security and driver updates only, permanently blocking feature updates.
# Prevents unwanted system changes and re-installed bloatware.
# Note: For Windows Home, use the regular variant (lasts 365 days).
# Special thanks to Skull Crusher (zombiehunternr1).

$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# Exclude non-security classifications (drivers are intentionally NOT excluded)
$excludedClassifications = @(
    "{e6cf1350-c01b-414d-a61f-263d3d4dd9f9}",  # Critical Updates
    "{b54e7d24-7add-49f4-88bb-9837d47477fb}",  # Feature Packs
    "{68c5b0a3-d1a6-4553-ae49-01d3a7827828}",  # Service Packs
    "{b4832bd8-e735-4766-9727-7d0ffa644277}",  # Tools
    "{28bc8804-5382-4bae-93aa-13c905f28542}",  # Update Rollups
    "{cd5ffd1e-e257-4a05-9d88-c83a7125d4c9}",  # Updates
    "{0f1afbec-90ef-4651-9e37-030fedc944c8}",  # Non-critical
    "{9920c092-3d99-4a1b-865a-673135c5a4fc}"   # Feature Updates
) -join ";"

# Create registry keys if missing
if (-not (Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}

# Configure classifications + notify before install. Drivers are NOT blocked.
Set-ItemProperty -Path $registryPath -Name "ExcludeUpdateClassifications" -Value $excludedClassifications -Type String -Force
Set-ItemProperty -Path $registryPath -Name "AUOptions" -Value 2 -Type DWord -Force  # Notify before install

# Restart Windows Update service
Restart-Service -Name wuauserv -Force

Write-Host "Security updates only. Drivers are NOT blocked."