<#
.SYNOPSIS
    Injects intentional Active Directory misconfigurations that later red-team
    projects will exploit and blue-team projects will detect. Each one mirrors a
    real, common finding from AD pentests.

.NOTES
    Run as LAB\Administrator on DC01 AFTER 02-seed-identities.ps1.
    Idempotent: re-running re-applies the same state without duplicating objects.

    >>> This script deliberately WEAKENS the domain. Only ever run it inside the
    >>> isolated lab. It is the whole point of the lab, but it is dangerous anywhere
    >>> real. <<<

    Reviewer note: read the WHY blocks below - each explains the attack the
    misconfiguration enables and why a defender should care. This is where I show I
    understand *offense and defense of the same finding*.
#>

[CmdletBinding()]
param([string]$Domain = 'lab.local')

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$baseDN   = ($Domain.Split('.') | ForEach-Object { "DC=$_" }) -join ','
$svcOU    = "OU=ServiceAccounts,OU=LAB,$baseDN"

$svcPwd = Read-Host -AsSecureString -Prompt "Password for the service account (make it weak/crackable, e.g. Password123!)"

# =================================================================================
# MISCONFIG 1 - Kerberoastable service account (svc_sql)
# =================================================================================
# WHAT: a normal user account with a Service Principal Name (SPN) registered on it.
# WHY IT'S RISKY: any authenticated domain user can request a Kerberos service ticket
#   (TGS) for an account that has an SPN. The ticket is encrypted with the service
#   account's NTLM hash, so the attacker takes it offline and cracks the password
#   (Kerberoasting, MITRE ATT&CK T1558.003). Because svc_sql has a weak password and,
#   worse, is often over-privileged, cracking it can hand the attacker a foothold or
#   even domain escalation. Real SQL/IIS service accounts get set up exactly like this.
# DETECTION ANGLE (blue): watch for Event ID 4769 (TGS request) using RC4 encryption
#   (0x17) for accounts with SPNs - that pattern is the Kerberoast signature.
$svcSql = 'svc_sql'
if (-not (Get-ADUser -Filter "SamAccountName -eq '$svcSql'" -ErrorAction SilentlyContinue)) {
    New-ADUser -SamAccountName $svcSql -Name 'svc_sql (SQL Service)' `
        -UserPrincipalName "$svcSql@$Domain" -Path $svcOU `
        -AccountPassword $svcPwd -Enabled $true -PasswordNeverExpires $true
    Write-Host "[+] Created service account $svcSql" -ForegroundColor Green
}
# Register an SPN -> makes it Kerberoastable.
setspn -S "MSSQLSvc/dc01.$Domain:1433" $svcSql | Out-Null
Write-Host "[!] MISCONFIG 1: $svcSql is now Kerberoastable (SPN MSSQLSvc/dc01.$Domain:1433)" -ForegroundColor Yellow

# =================================================================================
# MISCONFIG 2 - AS-REP roastable user (no Kerberos pre-auth)
# =================================================================================
# WHAT: disable Kerberos pre-authentication on a normal user (b.otieno, helpdesk).
# WHY IT'S RISKY: with pre-auth off, anyone can ask the DC for that user's AS-REP
#   without proving they know the password. The AS-REP is encrypted with the user's
#   key, so it's crackable offline (AS-REP Roasting, T1558.004) - no valid domain
#   creds needed at all. It's a favourite because it can be done pre-authentication.
# DETECTION ANGLE (blue): Event ID 4768 (AS-REQ) with pre-auth type 0 / RC4 is the tell.
$asrepUser = 'b.otieno'
if (Get-ADUser -Filter "SamAccountName -eq '$asrepUser'" -ErrorAction SilentlyContinue) {
    Set-ADAccountControl -Identity $asrepUser -DoesNotRequirePreAuth $true
    Write-Host "[!] MISCONFIG 2: $asrepUser no longer requires Kerberos pre-auth (AS-REP roastable)" -ForegroundColor Yellow
}

# =================================================================================
# MISCONFIG 3 - Over-permissioned user (helpdesk with DCSync rights)
# =================================================================================
# WHAT: grant b.otieno (a Tier-2 helpdesk account) the replication rights
#   (DS-Replication-Get-Changes + -All) on the domain root.
# WHY IT'S RISKY: those two extended rights are exactly what DCSync abuses. Any
#   principal holding them can impersonate a DC and pull password hashes for ANY
#   account in the domain - including krbtgt and Domain Admins (T1003.006). Handing
#   replication rights to a low-tier account is a classic "delegation gone wrong":
#   it looks like a helpdesk convenience but is effectively domain compromise.
# DETECTION ANGLE (blue): Event ID 4662 with the replication GUIDs, and 4769/4624
#   from a non-DC host performing replication.
$repGuids = @{
    'Get-Changes'     = '1131f6aa-9c07-11d1-f79f-00c04fc2dcd2'
    'Get-Changes-All' = '1131f6ad-9c07-11d1-f79f-00c04fc2dcd2'
}
$user = Get-ADUser $asrepUser
$sid  = [System.Security.Principal.SecurityIdentifier]$user.SID
$rootDN = (Get-ADDomain).DistinguishedName
$acl = Get-Acl "AD:$rootDN"
foreach ($guid in $repGuids.Values) {
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid, 'ExtendedRight', 'Allow', [Guid]$guid)
    $acl.AddAccessRule($ace)
}
Set-Acl -Path "AD:$rootDN" -AclObject $acl
Write-Host "[!] MISCONFIG 3: $asrepUser granted DCSync (replication) rights on the domain" -ForegroundColor Yellow

# =================================================================================
# MISCONFIG 4 (bonus) - stale over-privileged membership
# =================================================================================
# WHAT: add the IT-Helpdesk group's b.otieno into Domain Admins "temporarily".
# WHY IT'S RISKY: nested/forgotten Domain Admins membership is one of the most common
#   real-world privilege-escalation paths. BloodHound lights these up instantly. I
#   include it so the graph-based enumeration project has something to find.
Add-ADGroupMember -Identity 'Domain Admins' -Members $asrepUser -ErrorAction SilentlyContinue
Write-Host "[!] MISCONFIG 4: $asrepUser added to Domain Admins (over-privileged)" -ForegroundColor Yellow

Write-Host "`n[*] Misconfigurations injected. Document them in docs/verification.md and" -ForegroundColor Cyan
Write-Host "    exploit them from KALI01 in the red-team projects." -ForegroundColor Cyan
Write-Host "    To reset, restore the DC01 'pre-attack-clean' snapshot." -ForegroundColor Cyan
