# Verification checklist

Proof the lab is built correctly and the **attack → log → detect** pipeline works.
Work top to bottom; each item has a command/action and the expected result. Drop a
screenshot where the placeholders are — those are the artifacts a reviewer skims.

> **Reviewer note:** this file is the evidence. The screenshots below are where you
> can confirm — without building anything — that AD, Sysmon, and Wazuh actually work.

---

## 1. Network isolation
- [ ] Every VM pings the DC: `ping 10.10.10.10` succeeds from WS01/UB01/KALI01/WAZUH01.
- [ ] With NAT detached, a lab VM **cannot** reach the internet (`ping 8.8.8.8` fails).
- [ ] AD DNS resolves: `nslookup dc01.lab.local 10.10.10.10` returns `10.10.10.10`.

📸 _screenshot: `nslookup dc01.lab.local` + a successful/blocked ping_

## 2. Active Directory
- [ ] `Get-ADDomain` on DC01 shows `lab.local`, mode `WinThreshold`.
- [ ] `Get-ADUser -Filter *` lists the 10 seeded users + `svc_sql`.
- [ ] `(Get-ADUser svc_sql -Properties ServicePrincipalName).ServicePrincipalName`
      shows `MSSQLSvc/dc01.lab.local:1433`.
- [ ] `(Get-ADUser b.otieno -Properties DoesNotRequirePreAuth).DoesNotRequirePreAuth`
      is `True`.
- [ ] `Get-ADGroupMember 'Domain Admins'` includes `b.otieno` (intentional).

📸 _screenshot: `Get-ADUser -Filter *` table + the svc_sql SPN_

## 3. Domain join (WS01) ✅ verified 2026-07-26
- [x] `(Get-CimInstance Win32_ComputerSystem).Domain` on WS01 = `lab.local`
      (also `PartOfDomain=True`).
- [x] Secure channel to the DC is healthy: `Test-ComputerSecureChannel` = **True**.
- [x] Logon screen shows the domain **"Other user"** tile (domain-join indicator).
- [ ] A domain user (`LAB\a.mokaya`) interactive login — deferred (agent/telemetry
      work is driven headless via guestcontrol; not required for the join proof).

📸 _evidence: [`../setup/evidence/ws01/07-domain-join-verified.txt`](../setup/evidence/ws01/07-domain-join-verified.txt) + [`04-joined-desktop.png`](../setup/evidence/ws01/04-joined-desktop.png) (logon screen with domain "Other user")_

## 4. Sysmon telemetry (DC01, WS01) — WS01 ✅ 2026-07-26
- [x] **WS01** `Get-Service Sysmon64` = **Running** (Sysmon v15.21).
- [x] **WS01** `Get-WinEvent -LogName 'Microsoft-Windows-Sysmon/Operational'` returns
      recent events including **ID 1 (process create)**.
- [x] SwiftOnSecurity config loaded — installer reported *"Configuration file
      validated"* (schema 4.50) via `scripts/sysmon/install-sysmon.ps1`.

📸 _screenshot: recent Sysmon Operational events (WS01)_

## 5. Wazuh stack (WAZUH01) ✅ verified 2026-07-25
- [x] `docker compose ps` shows indexer + manager + dashboard running (Wazuh 4.9.0).
- [x] Indexer cluster health is **green** (`GET /_cluster/health`), 11/11 shards active.
- [x] Manager API authenticates and reports `v4.9.0 server`.
- [x] Dashboard loads at **`https://10.10.10.50`** and serves the Wazuh login app.

📸 _evidence: [`../setup/evidence/wazuh01-stack-verification.txt`](../setup/evidence/wazuh01-stack-verification.txt) — dashboard login screenshot to be added on the next run with a browser_

## 6. Every host is an Active agent  (DC01 2025-07-25 · WS01 2026-07-26)
- [x] **DC01** enrolled and **Active** — `agent_control -l` lists `ID: 001, DC01, Active`.
- [x] **WS01** enrolled and **Active** — `ID: 002, WS01, Active`. Manager reports its OS
      (`Windows 11 Enterprise Evaluation`), agent `v4.9.0`, and a live keep-alive, so it
      is actively reporting — not just registered.
- [ ] UB01 agent (pending that host being built).

> RAM note: DC01 shows *Disconnected* whenever it is powered off to fit the phase (see
> `docs/low-ram-operating-guide.md`); WS01+WAZUH01 is the phase used to verify this.

📸 _evidence: [`../setup/evidence/ws01/05-agent-control-active.txt`](../setup/evidence/ws01/05-agent-control-active.txt) (000/001/002 list) + [`06-ws01-agent-detail.txt`](../setup/evidence/ws01/06-ws01-agent-detail.txt) (WS01 Active + OS/version)_

## 7. End-to-end: Windows event + Sysmon reach the SIEM
- [ ] Run `whoami /all` on WS01.
- [ ] In **Discover/Threat Hunting**, `agent.name: WS01` +
      `data.win.system.channel: "Microsoft-Windows-Sysmon/Operational"` returns the
      matching process-create (ID 1) event.

📸 _screenshot: the Sysmon process-create event for WS01 in Wazuh_

## 8. End-to-end: a real detection fires  ✅ 2026-07-25
- [x] From KALI01, Kerberoasted `svc_sql` (`impacket-GetUserSPNs lab.local/a.mokaya -request`).
- [x] Wazuh **rule 100010** fired: Kerberos TGS (Event 4769, RC4 0x17) alert for `svc_sql`,
      agent DC01, source `10.10.10.40` — the detection of misconfig #1.

📸 _evidence: [`../projects/01-kerberoasting/evidence/05-wazuh-kerberoast-alert.png`](../projects/01-kerberoasting/evidence/05-wazuh-kerberoast-alert.png) + [`06-wazuh-alert-detail.png`](../projects/01-kerberoasting/evidence/06-wazuh-alert-detail.png)_

---

### Sign-off
When every box is checked and the eight screenshots are captured, the lab is proven:
isolated network ✅, AD with seeded weaknesses ✅, Sysmon telemetry ✅, Wazuh
ingesting from every host ✅, and a real attack producing a real alert ✅.
