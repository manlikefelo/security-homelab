# 02 — Active Directory domain (DC01) + workstation join

Goal: promote DC01 to a Domain Controller for **`lab.local`**, build a realistic org
(users, groups, OUs), inject the intentional weaknesses, then join WS01 to the domain.

> **Reviewer note:** the three PowerShell scripts in
> [../scripts/ad/](../scripts/ad/) are the heart of this project. Each is idempotent
> and prompts for secrets at runtime (nothing sensitive is committed).
> [`03-inject-misconfigs.ps1`](../scripts/ad/03-inject-misconfigs.ps1) documents,
> in comments, *why each misconfiguration is dangerous and how a defender detects it*
> — that's the file to read to judge my AD understanding.

---

## Prereqs
- DC01 built from the Windows Server 2022 eval ISO (guide 00), static IP `10.10.10.10`,
  DNS pointed at itself (guide 01).
- Copy the `scripts/ad/` folder onto DC01 (shared folder, or clone the repo there).

## Step 1 — Promote to Domain Controller
In an **elevated** PowerShell session on DC01:
```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd .\scripts\ad
.\01-install-adds.ps1
```
- You'll be prompted for a **DSRM password** (chosen at runtime — never stored).
- The VM **reboots** to complete promotion.
- **Snapshot** DC01 as `base-installed` after reboot.

## Step 2 — Seed the org (users, groups, OUs)
Log back in as **`LAB\Administrator`**, then:
```powershell
cd .\scripts\ad
.\02-seed-identities.ps1
```
- Prompts once for a **shared lab password** — deliberately weak (e.g. `Summer2026!`)
  so later spray/cracking demos work. The script explains why in-line.
- Creates OUs (`Users/Groups/ServiceAccounts/Workstations`), 8 groups, and 10 users
  from [`users.csv`](../scripts/ad/users.csv).

## Step 3 — Inject the intentional misconfigurations
```powershell
.\03-inject-misconfigs.ps1
```
Prompts for a weak **service-account password**, then applies:

| # | Misconfiguration | Enables (red) | Detect via (blue) |
|---|------------------|---------------|-------------------|
| 1 | `svc_sql` with an SPN | **Kerberoasting** (T1558.003) | 4769 TGS w/ RC4 for SPN accounts |
| 2 | `b.otieno` no Kerberos pre-auth | **AS-REP roasting** (T1558.004) | 4768 AS-REQ pre-auth type 0 |
| 3 | `b.otieno` granted replication rights | **DCSync** (T1003.006) | 4662 w/ replication GUIDs |
| 4 | `b.otieno` in Domain Admins | **Priv-esc path** (BloodHound) | group-membership audit / 4728 |

> Read the WHY comment block above each misconfig in the script — that's where I
> explain the risk in defender terms.

**Snapshot** DC01 as `configured`, then again as `pre-attack-clean` (the state I
revert to before each red-team run).

## Step 4 — Join WS01 to the domain
On WS01 (Windows 10/11 eval), static IP `10.10.10.20`, DNS `10.10.10.10`:
```powershell
# Confirm the DC resolves first:
nslookup dc01.lab.local 10.10.10.10
# Join:
Add-Computer -DomainName lab.local -Credential (Get-Credential LAB\Administrator) -Restart
```
After reboot, log in as a domain user (e.g. `LAB\a.mokaya`) to confirm the join.
**Snapshot** WS01 as `configured`.

## Verify
- `Get-ADUser -Filter *` on DC01 lists the seeded users.
- `Get-ADUser svc_sql -Properties ServicePrincipalName` shows the SPN.
- `Get-ADUser b.otieno -Properties DoesNotRequirePreAuth` shows `True`.
- WS01 appears in **AD Users and Computers → Computers**.

➡️ Next: **[03-wazuh-siem.md](03-wazuh-siem.md)**
