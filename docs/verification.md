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

## 3. Domain join (WS01)
- [ ] `(Get-CimInstance Win32_ComputerSystem).Domain` on WS01 = `lab.local`.
- [ ] A domain user (`LAB\a.mokaya`) can log in interactively on WS01.
- [ ] WS01 appears under **AD Users and Computers → Computers** on DC01.

📸 _screenshot: WS01 System properties showing domain `lab.local`_

## 4. Sysmon telemetry (DC01, WS01)
- [ ] `Get-Service Sysmon64` = Running.
- [ ] `Get-WinEvent -LogName 'Microsoft-Windows-Sysmon/Operational' -MaxEvents 5`
      returns recent events (IDs 1/3).
- [ ] The SwiftOnSecurity config is loaded (`Sysmon64.exe -c` shows the schema).

📸 _screenshot: recent Sysmon Operational events_

## 5. Wazuh stack (WAZUH01)
- [ ] `docker compose ps` shows indexer + manager + dashboard running/healthy.
- [ ] Dashboard loads at `https://10.10.10.50:5601` and you can log in.

📸 _screenshot: Wazuh dashboard overview_

## 6. Every host is an Active agent
- [ ] Dashboard **Agents** view shows DC01, WS01, UB01 (and WAZUH01) as **Active**.
- [ ] `agent_control -l` in the manager container lists the same agents.

📸 _screenshot: Wazuh Agents page with all hosts Active_

## 7. End-to-end: Windows event + Sysmon reach the SIEM
- [ ] Run `whoami /all` on WS01.
- [ ] In **Discover/Threat Hunting**, `agent.name: WS01` +
      `data.win.system.channel: "Microsoft-Windows-Sysmon/Operational"` returns the
      matching process-create (ID 1) event.

📸 _screenshot: the Sysmon process-create event for WS01 in Wazuh_

## 8. End-to-end: a real detection fires
- [ ] From KALI01, Kerberoast `svc_sql` (e.g. `GetUserSPNs.py lab.local/a.mokaya -request`).
- [ ] In Wazuh, confirm a Kerberos TGS (Event 4769, RC4) alert appears for the SPN
      account — the detection of misconfig #1.

📸 _screenshot: the Kerberoasting-related alert in Wazuh_

---

### Sign-off
When every box is checked and the eight screenshots are captured, the lab is proven:
isolated network ✅, AD with seeded weaknesses ✅, Sysmon telemetry ✅, Wazuh
ingesting from every host ✅, and a real attack producing a real alert ✅.
