# Project 01 — Kerberoasting (T1558.003)

Attack the `svc_sql` service account (misconfig #1), crack its password offline, then
detect the attack in Wazuh.

---

## 1. Scenario
`svc_sql` is a normal user account that carries a Service Principal Name
(`MSSQLSvc/dc01.lab.local:1433`). In Kerberos, **any authenticated domain user** can
request a service ticket (TGS) for an account with an SPN. That ticket is encrypted
with the service account's password hash — so an attacker requests it, takes it
offline, and brute-forces the password. No admin rights and no touching the target
service are needed. Real SQL/IIS/web service accounts are set up exactly this way,
which is why Kerberoasting is one of the most common AD attacks in the wild.

**Phase:** Red — power on **KALI01 + DC01** only (Wazuh off). See operating guide.

## 2. Attack (from KALI01)

Prereqs: Kali can resolve the domain (DNS → 10.10.10.10) and you have **any** valid
domain user's credentials (here `a.mokaya`, a normal user — that's the point).

```bash
# Impacket's GetUserSPNs requests TGS tickets for all SPN accounts and prints hashes
impacket-GetUserSPNs lab.local/a.mokaya -dc-ip 10.10.10.10 -request \
    -outputfile kerberoast.hashes
# You'll be prompted for a.mokaya's password (the weak lab password).
```

Expected: a `$krb5tgs$23$...` hash for `svc_sql` written to `kerberoast.hashes`.
The `23` = RC4 (etype 0x17) — the crackable encryption type.

Crack it offline with hashcat (mode 13100 = Kerberoast TGS-REP):
```bash
hashcat -m 13100 kerberoast.hashes /usr/share/wordlists/rockyou.txt
```
Because `svc_sql` was given a weak password on purpose, this cracks in seconds and
you recover the plaintext.

> **What I proved:** starting from a *low-privileged* domain user, I recovered a
> service account's password with no elevation — a realistic foothold-to-escalation step.

## 3. Telemetry this generates
On DC01, each TGS request writes **Event ID 4769** (Kerberos service ticket requested)
with:
- `Ticket Encryption Type: 0x17` (RC4) — modern accounts should use AES (0x12).
- `Service Name: svc_sql`.
A burst of 4769s with RC4 for SPN accounts from one user is the Kerberoast signature.

## 4. Detection (in Wazuh — blue phase)
Bring up WAZUH01 (see operating guide). The DC's Wazuh agent forwards Security events.
Search / alert on:
```
data.win.system.eventID:4769 AND data.win.eventdata.ticketEncryptionType:0x17
```
A custom rule for this lives in
[`../../wazuh/custom-rules/local_rules.xml`](../../wazuh/custom-rules/local_rules.xml)
(rule id `100010`). It fires when RC4 TGS requests exceed a threshold.

## 5. Remediation (how a defender fixes it)
- Give service accounts **long random passwords** (25+ chars) or use **Group Managed
  Service Accounts (gMSA)** so the password is machine-managed and un-crackable.
- Force **AES** encryption on the account (`msDS-SupportedEncryptionTypes`), removing RC4.
- Remove unnecessary SPNs.
- Alert on RC4 TGS requests (the rule above).

Reset the lab afterward by restoring DC01's `pre-attack-clean` snapshot.

## 6. Evidence
- 📸 `GetUserSPNs` output showing the `svc_sql` hash
- 📸 hashcat cracking the password
- 📸 the Wazuh alert (rule 100010) for the RC4 TGS burst

## 7. ATT&CK coverage matrix

How this project's attack maps onto MITRE ATT&CK, and which step my detection covers.
✅ = I have a Wazuh detection that fires on this step; ⬜ = performed in the attack but
not the point where I detect.

| Tactic | Technique (ID) | Attacker action in this lab | Telemetry | Detection | Wazuh rule |
|--------|----------------|------------------------------|-----------|-----------|------------|
| Credential Access | **Kerberoasting (T1558.003)** | `GetUserSPNs` requests an RC4 TGS for `svc_sql` and dumps the hash | DC01 Event **4769**, `ticketEncryptionType 0x17` (RC4) | ✅ | **100010** (level 10) |
| Credential Access | Brute Force: Password Cracking (T1110.002) | Offline crack of the TGS-REP hash (John/hashcat) → `svc_sql : P@ssw0rd` | none — offline, off-host | ⬜ (offline, no telemetry by design) | — |

**One-line summary:** detects Kerberoasting at the ticket-request step (4769 / RC4)
via rule **100010** → MITRE **T1558.003** (Credential Access).
