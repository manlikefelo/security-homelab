# Project 04 — BloodHound / AD enumeration: Run Log

Actual execution record of the attack described in [`README.md`](README.md).
Run on **2026-07-31** from KALI01 (`10.10.10.40`) against DC01 (`10.10.10.10`).
Structured on **PTES** phases and mapped to **MITRE ATT&CK** technique IDs — every
action carries its ATT&CK ID.

---

## Environment at run time
- **KALI01** — Kali 2026.2, `felix@felix`, eth1 = host-only `10.10.10.40/24`.
- **DC01** — `lab.local` DC, `10.10.10.10`.
- **Credential:** `a.mokaya : Autumn2026!` — an **ordinary, low-privileged** domain
  user. The point of this project: *any* authenticated user can enumerate the whole
  directory. No special rights needed.
- Tooling shipped with Kali: `bloodhound-python` 1.9.0 (the SharpHound-equivalent
  Python ingestor).

## PTES phase mapping

| PTES phase | ATT&CK tactic | Action in this project | ATT&CK ID |
|------------|---------------|------------------------|-----------|
| Intelligence Gathering | Discovery | Enumerate every user/group/computer/ACL over LDAP (BloodHound collection) | **T1087.002** (Account Discovery: Domain) |
| Intelligence Gathering | Discovery | …enumerate domain **groups**/memberships | **T1069.002** (Permission Groups Discovery: Domain) |
| Intelligence Gathering | Discovery | …enumerate domain trusts/topology | T1482 (Domain Trust Discovery) |
| Analysis | — | Read the graph: shortest paths to Domain Admin, DCSync holders, roastable users | — (offline analysis of collected data) |
| Reporting / detection | — | Blue-phase detection of the 4661/4662 read burst in Wazuh | — |

## Step 1 — Intelligence Gathering: collect the whole domain graph (T1087.002 / T1069.002)

Run as a low-priv user; `-c All` pulls users, groups, ACLs, sessions, computers:

```bash
bloodhound-python -u a.mokaya -p 'Autumn2026!' -d lab.local -ns 10.10.10.10 \
    -c All --zip
```

Output ([`evidence/bloodhound_collection_output.txt`](evidence/bloodhound_collection_output.txt)):
```
INFO: Found 15 users
INFO: Found 60 groups
INFO: Found 2 gpos
INFO: Found 6 ous
INFO: Found 19 containers
INFO: Done in 00M 31S
INFO: Compressing output into 20260731054145_bloodhound.zip
```
The whole directory read in **31 seconds** by an ordinary user → a `*_bloodhound.zip`
of 7 JSON files ready to graph.
Evidence: [`evidence/01-bloodhound-collection.png`](evidence/01-bloodhound-collection.png),
[`evidence/02-collection-zip-contents.png`](evidence/02-collection-zip-contents.png).

> Kerberos on port 88 briefly refused, so the collector fell back to NTLM auth — a
> harmless, common quirk; the LDAP enumeration (the noisy part) proceeded normally.

## Step 2 — Analysis: read the attack paths out of the graph

The BloodHound GUI (BloodHound CE + Neo4j) is very RAM-hungry and isn't installed on
this constrained host, so instead of the GUI I read the same **edges** directly out of
the collected JSON with a small script — which independently confirms every planted
misconfiguration from Projects 01–03:
Evidence: [`evidence/04-attack-paths-from-graph.png`](evidence/04-attack-paths-from-graph.png).

| Path | What the graph shows | Ties back to |
|------|----------------------|--------------|
| **Domain Admins** | `b.otieno` (SID …-1112) is a member — the instant win | misconfig #4 |
| **DCSync rights** | `b.otieno` holds **GetChanges** *and* **GetChangesAll** on the domain | misconfig #3 (Project 03) |
| **Kerberoastable** | `svc_sql` has SPN `MSSQLSvc/dc01.lab.local:1433` | misconfig #1 (Project 01) |
| **AS-REP roastable** | `b.otieno` has `dontreqpreauth=True` | misconfig #2 (Project 02) |

`b.otieno` sits at the centre of the graph — in Domain Admins, holding DCSync rights,
and AS-REP roastable. That is exactly the "one account, many edges" picture BloodHound
is built to surface, and every edge maps back to a specific, explainable finding.

## Result

From a nobody user I mapped the entire domain and read every privilege-escalation path
to Domain Admin — the same view an attacker uses to plan takeover and a defender uses
to cut the paths first. It visually unifies the three earlier attacks: they are all
edges leading to full compromise, all through `b.otieno`.

## Blue phase — detection fired (2026-07-31)

Enumeration is a **rate** signal, not a single-event signature — so rule **100013**
uses frequency+timeframe (≥15 directory-access events from one source in 60s) rather
than a single-event match. The auditing enabled for Project 03 (Directory Service
Access) is what produces the 4662 object-access events the collection generates.

With WAZUH01 up and DC01's agent Active, the collection burst tripped the threshold and
rule **100013** matched. Filtering `rule.id:100013` returns the hits (fired 2×):

| Field | Value |
|-------|-------|
| rule.id / level | **100013** / 8 |
| rule.description | Directory enumeration burst (possible BloodHound/SharpHound collection) [T1087] |
| rule.mitre | **T1087.002** (Discovery → Domain Account) |
| rule.frequency | **15** (events in the window that trip the rule) |
| agent.name | **DC01** (id 001) |
| triggering eventID | **4662** (directory object access), amid the correlated burst |

Full alert: [`evidence/wazuh_alert_100013.json`](evidence/wazuh_alert_100013.json).
Dashboard: [`evidence/03-wazuh-enumeration-alert.png`](evidence/03-wazuh-enumeration-alert.png)
— Wazuh Discover filtered to `rule.id:100013`, **2 hits** rendered from DC01, the
`_source` rows showing the correlated 4662 read burst (subject `b.otieno`).

> **Honest nuance (worth an interview):** this is the noisiest detection in the lab.
> A single Kerberoast (4769/RC4) or DCSync (4662/replication-GUID) is a sharp,
> high-confidence signature. Enumeration blends into normal directory traffic, so a
> rate rule trades precision for coverage and needs tuning (threshold, whitelisting
> legit scanners) to avoid false positives. Detecting *breadth of reads* is
> fundamentally harder than detecting a specific dangerous operation — and saying so
> is part of understanding it.
>
> **Screenshot note:** the rendered dashboard (03) was captured the same way as
> Project 03 — set `wazuh-alerts-*` as the default index pattern server-side, then open
> the classic `/app/discover` route, which binds it and renders the hits. Driven
> entirely by keyboard (GNOME's Wayland portal blocks synthetic mouse clicks).

## Remediation (verified understanding)
- **Cut the paths:** remove `b.otieno` from Domain Admins and strip its replication
  rights (Projects 03/04 remediations); fix the SPN/pre-auth findings (01/02).
- Adopt **Tiered Administration** and least privilege so no such edges exist.
- Run BloodHound **defensively** on a schedule and treat any new Domain-Admin path as
  an incident.
- Alert on directory-enumeration bursts (rule 100013), tuned to your environment.

## Evidence

**Red phase** — full-screen KALI01 GUI terminal:

| # | Shot | What it shows |
|---|------|---------------|
| 1 | [`evidence/01-bloodhound-collection.png`](evidence/01-bloodhound-collection.png) | `bloodhound-python -c All` enumerating the whole domain as low-priv `a.mokaya` — T1087.002/T1069.002 |
| 2 | [`evidence/02-collection-zip-contents.png`](evidence/02-collection-zip-contents.png) | The resulting `_bloodhound.zip` — 7 JSON files (users/groups/computers/…) |
| 4 | [`evidence/04-attack-paths-from-graph.png`](evidence/04-attack-paths-from-graph.png) | Attack paths read from the collected graph: b.otieno in Domain Admins + DCSync rights, svc_sql Kerberoastable, b.otieno AS-REP roastable |

**Blue phase** — Wazuh:

| # | Shot / file | What it shows |
|---|-------------|---------------|
| 3 | [`evidence/03-wazuh-enumeration-query.png`](evidence/03-wazuh-enumeration-query.png) | Discover filtered to `rule.id:100013` on the live SIEM |
| — | [`evidence/wazuh_alert_100013.json`](evidence/wazuh_alert_100013.json) | Full alert: rule 100013 / T1087.002 / frequency 15 / DC01 / 4662 burst |

Raw output: [`evidence/bloodhound_collection_output.txt`](evidence/bloodhound_collection_output.txt).
