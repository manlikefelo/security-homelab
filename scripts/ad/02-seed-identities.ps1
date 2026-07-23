<#
.SYNOPSIS
    Builds a realistic-looking org inside lab.local: OUs, security groups, and users
    from users.csv. This is the "clean" baseline BEFORE any intentional weakness is
    introduced (that happens in 03-inject-misconfigs.ps1).

.NOTES
    Run as LAB\Administrator on DC01 AFTER 01-install-adds.ps1 has promoted the DC.
    Idempotent: existing OUs/groups/users are detected and skipped, so re-running
    only creates what's missing.

    Reviewer note: no passwords live in this file. A single lab password is prompted
    once at runtime and applied to the seed users. It is a DELIBERATELY weak lab
    password so later password-spray / cracking demos succeed - see the WHY below.
#>

[CmdletBinding()]
param(
    [string]$CsvPath = (Join-Path $PSScriptRoot 'users.csv'),
    [string]$Domain  = 'lab.local'
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

# lab.local -> "DC=lab,DC=local"
$baseDN = ($Domain.Split('.') | ForEach-Object { "DC=$_" }) -join ','

# --- Password for the seed users -------------------------------------------------
# WHY prompt: same reason as the DSRM password - never commit a credential.
# WHY intentionally weak: several red-team projects (password spraying, NTLM/Kerberos
# cracking) need the seed accounts to use a crackable password. Using a single weak
# password across the org also mirrors a real, common misconfiguration.
$labPwd = Read-Host -AsSecureString -Prompt "Enter the shared lab user password (use something weak, e.g. Summer2026!)"

# --- 1. Organizational Units -----------------------------------------------------
$ouLab = "OU=LAB,$baseDN"
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouLab'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name 'LAB' -Path $baseDN -ProtectedFromAccidentalDeletion $false
    Write-Host "[+] Created OU=LAB" -ForegroundColor Green
}
foreach ($sub in 'Users','Groups','ServiceAccounts','Workstations') {
    $ouDN = "OU=$sub,$ouLab"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouDN'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $sub -Path $ouLab -ProtectedFromAccidentalDeletion $false
        Write-Host "[+] Created OU=$sub" -ForegroundColor Green
    }
}
$usersOU  = "OU=Users,$ouLab"
$groupsOU = "OU=Groups,$ouLab"

# --- 2. Security groups ----------------------------------------------------------
$groups = 'IT-Admins','IT-Helpdesk','Finance','HR','Sales','Engineering','Executives','FileShare-RW'
foreach ($g in $groups) {
    if (-not (Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $g -GroupScope Global -GroupCategory Security -Path $groupsOU
        Write-Host "[+] Created group $g" -ForegroundColor Green
    }
}

# --- 3. Users from CSV -----------------------------------------------------------
Import-Csv $CsvPath | ForEach-Object {
    $sam = $_.SamAccountName
    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Host "[=] User $sam exists - skipping" -ForegroundColor DarkGray
        return
    }
    $upn = "$sam@$Domain"
    New-ADUser `
        -SamAccountName        $sam `
        -UserPrincipalName     $upn `
        -Name                  "$($_.GivenName) $($_.Surname)" `
        -GivenName             $_.GivenName `
        -Surname               $_.Surname `
        -DisplayName           "$($_.GivenName) $($_.Surname)" `
        -Department            $_.Department `
        -Title                 $_.Title `
        -Path                  $usersOU `
        -AccountPassword       $labPwd `
        -Enabled               $true `
        -ChangePasswordAtLogon $false
    Add-ADGroupMember -Identity $_.Group -Members $sam
    Write-Host "[+] Created user $sam ($($_.Department)) -> $($_.Group)" -ForegroundColor Green
}

Write-Host "`n[*] Baseline org built. Next: run 03-inject-misconfigs.ps1" -ForegroundColor Cyan
