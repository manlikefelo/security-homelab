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
- 📸 BloodHound "Shortest Path to Domain Admins" showing `b.otieno`
- 📸 the DCSync-rights and Kerberoastable queries
- 📸 Wazuh alert (rule 100013) for the enumeration burst
