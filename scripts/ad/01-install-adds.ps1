<#
.SYNOPSIS
    Installs Active Directory Domain Services + DNS and promotes DC01 to the first
    Domain Controller of a new forest: lab.local.

.NOTES
    Run this in an ELEVATED PowerShell session on DC01 only.
    The machine REBOOTS at the end of promotion. After reboot, log in as
    LAB\Administrator and run 02-seed-identities.ps1.

    Idempotent: safe to re-run. If the role/forest already exists it is skipped.

    Reviewer note: I keep the DSRM password OUT of this script: it is prompted for
    at runtime so no secret is ever committed to git.
#>

[CmdletBinding()]
param(
    [string]$DomainName    = 'lab.local',
    [string]$NetbiosName   = 'LAB'
)

$ErrorActionPreference = 'Stop'

Write-Host "[*] Installing AD DS + DNS roles..." -ForegroundColor Cyan
if (-not (Get-WindowsFeature AD-Domain-Services).Installed) {
    Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
} else {
    Write-Host "    AD-Domain-Services already installed - skipping." -ForegroundColor DarkGray
}

# Already a DC? Then don't try to promote again (idempotency).
$isDC = (Get-CimInstance Win32_ComputerSystem).DomainRole -in 4,5
if ($isDC) {
    Write-Host "[=] This host is already a Domain Controller - nothing to promote." -ForegroundColor Yellow
    return
}

Import-Module ADDSDeployment

# Prompt for the Directory Services Restore Mode password at runtime.
# WHY prompt instead of hardcode: committing a credential to a public portfolio repo
# is exactly the kind of finding this lab is meant to *teach against*.
$dsrm = Read-Host -AsSecureString -Prompt "Enter a Directory Services Restore Mode (DSRM) password"

Write-Host "[*] Promoting to Domain Controller for forest '$DomainName'..." -ForegroundColor Cyan
Install-ADDSForest `
    -DomainName                    $DomainName `
    -DomainNetbiosName             $NetbiosName `
    -SafeModeAdministratorPassword $dsrm `
    -InstallDns `
    -DomainMode                    'WinThreshold' `
    -ForestMode                    'WinThreshold' `
    -NoRebootOnCompletion:$false `
    -Force

# (The machine reboots here. Continue with 02-seed-identities.ps1 after login.)
