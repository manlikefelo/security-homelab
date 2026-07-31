# Project 04 — BloodHound attack-path mapping (T1069 / T1087)

Collect the domain graph from KALI01 and let BloodHound reveal the privilege-escalation
paths created by the misconfigurations — including `b.otieno`'s forgotten Domain
Admins membership (misconfig #4).

---

## 1. Scenario
BloodHound turns AD into a graph of "who can reach Domain Admin, and how." Attackers
use it to find the shortest path to domain takeover; defenders use it to find and cut
those paths first. This project ties the earlier findings together visually: the
Kerberoastable account, the DCSync rights, and the stale Domain Admins membership all
show up as edges leading to full compromise.

**Phase:** Red — power on **KALI01 + DC01** (any valid domain user is enough to collect).

## 2. Attack (from KALI01)
```bash
# Collect graph data with the Python collector (any domain creds).
bloodhound-python -u a.mokaya -p '<lab-password>' -d lab.local -ns 10.10.10.10 \
    -c All --zip
```
Then load the resulting `.zip` into the BloodHound GUI (BloodHound CE + Neo4j) and run
built-in queries:
- **"Find Shortest Paths to Domain Admins"**
- **"Find Principals with DCSync Rights"**
- **"Shortest Paths from Kerberoastable Users"**

Expected findings (all planted on purpose):
- `b.otieno` → member of **Domain Admins** (misconfig #4) — instant win.
- `b.otieno` → **GetChanges/GetChangesAll** on the domain (misconfig #3 — DCSync).
- `svc_sql` flagged **Kerberoastable** (misconfig #1).

> **What I proved:** I can enumerate an AD environment and read attack paths the way
> both an attacker and a defender do — and every path maps back to a specific,
> explainable misconfiguration.

## 3. Telemetry this generates
Collection is heavy LDAP reads → **Event ID 4661/4662** (object access) and a spike of
LDAP queries against the DC. It's noisy relative to normal user behaviour.

## 4. Detection (in Wazuh — blue phase)
Look for a single host issuing an unusual volume of LDAP/directory reads in a short
window:
```
data.win.system.eventID:(4661 OR 4662) AND data.win.eventdata.subjectUserName:a.mokaya
```
Custom rule `100013` in
[`../../wazuh/custom-rules/local_rules.xml`](../../wazuh/custom-rules/local_rules.xml)
flags directory-enumeration bursts. (Enumeration is inherently noisier to detect than
the sharp signatures in 01–03 — that nuance is worth calling out in an interview.)

## 5. Remediation
- **Cut the paths:** remove `b.otieno` from Domain Admins and strip its replication
  rights (Projects 03/04 remediations).
- Adopt Tiered Administration and least privilege so no such edges exist.
- Periodically run BloodHound **defensively** and treat new DA paths as incidents.

## 6. Evidence

**Red phase** — full-screen KALI01 GUI terminal:

| # | Shot | What it shows |
|---|------|---------------|
| 1 | [`evidence/01-bloodhound-collection.png`](evidence/01-bloodhound-collection.png) | `bloodhound-python -c All` enumerating the domain as low-priv `a.mokaya` |
| 2 | [`evidence/02-collection-zip-contents.png`](evidence/02-collection-zip-contents.png) | The `_bloodhound.zip` — 7 JSON files ready to graph |
| 4 | [`evidence/04-attack-paths-from-graph.png`](evidence/04-attack-paths-from-graph.png) | Attack paths from the graph: b.otieno in Domain Admins + DCSync rights, svc_sql Kerberoastable, b.otieno AS-REP roastable |

**Blue phase** — Wazuh:

| # | Shot / file | What it shows |
|---|-------------|---------------|
| 3 | [`evidence/03-wazuh-enumeration-query.png`](evidence/03-wazuh-enumeration-query.png) | Discover filtered to `rule.id:100013` on the live SIEM |
| — | [`evidence/wazuh_alert_100013.json`](evidence/wazuh_alert_100013.json) | Full alert: rule 100013 / T1087.002 / frequency 15 / 4662 burst |

Raw output: [`evidence/bloodhound_collection_output.txt`](evidence/bloodhound_collection_output.txt).
See [`RUN-LOG.md`](RUN-LOG.md) for the exact PTES-structured execution record.

## 7. ATT&CK coverage matrix

Structured on **PTES** phases; every action carries its **MITRE ATT&CK** ID.
✅ = detected by a Wazuh rule; ⬜ = performed but not the detection point.

| PTES phase | Tactic | Technique (ID) | Action in this lab | Telemetry | Detection | Wazuh rule |
|------------|--------|----------------|--------------------|-----------|-----------|------------|
| Intelligence Gathering | Discovery | **Account Discovery: Domain (T1087.002)** | `bloodhound-python -c All` enumerates all users | DC01 **4661/4662** read burst | ✅ | **100013** (level 8, freq 15/60s) |
| Intelligence Gathering | Discovery | Permission Groups Discovery: Domain (T1069.002) | Same run enumerates all groups/memberships | part of the same burst | ✅ (same rule) | 100013 |
| Intelligence Gathering | Discovery | Domain Trust Discovery (T1482) | Same run enumerates trusts/topology | part of the same burst | ⬜ (covered by the burst rule, not keyed on trusts) | — |
| Analysis | — | (graph reading — offline) | Read shortest paths to DA, DCSync holders, roastable users | none (offline) | ⬜ | — |

> **Note for a reviewer:** this is the **noisiest** detection in the lab by design.
> Enumeration is a *rate* signal, so rule 100013 uses frequency+timeframe, which trades
> precision for coverage — the opposite trade-off from the sharp single-event
> signatures in 01–03 (4769/RC4, 4768/preAuth-0, 4662/replication-GUID). Detecting
> "breadth of reads" is inherently harder than detecting one dangerous operation, and
> the rule needs tuning/whitelisting in production.

**One-line summary:** detects the BloodHound/SharpHound collection as a directory-read
burst via rule **100013** → MITRE **T1087.002** (Discovery). The graph itself unifies
Projects 01–03: every finding is an edge to Domain Admin, all through `b.otieno`.
