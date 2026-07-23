# 04 — Sysmon + Wazuh agents on every host

Goal: install Sysmon (SwiftOnSecurity config) on the Windows hosts for rich
telemetry, then install the Wazuh agent on **every** host so all logs flow to
WAZUH01. Finish by confirming Windows events + Sysmon are visible in the dashboard.

> **Reviewer note:** this guide closes the loop — after it, an action on any host
> becomes a searchable event in the SIEM. The Sysmon step is what makes Windows
> telemetry *useful* (process/network/image-load), not just security-audit noise.

---

## Part A — Sysmon on Windows hosts (DC01, WS01)
Attach each VM's NAT adapter (guide 01) so it can download, then, **elevated**:
```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd .\scripts\sysmon
.\install-sysmon.ps1
```
Verify:
```powershell
Get-Service Sysmon64
Get-WinEvent -LogName 'Microsoft-Windows-Sysmon/Operational' -MaxEvents 5
```
You should see event IDs like **1** (process create), **3** (network connect).

## Part B — Wazuh agent

### Windows (DC01, WS01)
Download the agent MSI from the dashboard (**Agents → Deploy new agent**) or wazuh.com,
then install pointing at the manager:
```powershell
# WAZUH_MANAGER = the SIEM IP; WAZUH_AGENT_NAME = this host
msiexec /i wazuh-agent-4.9.0.msi /q `
  WAZUH_MANAGER="10.10.10.50" WAZUH_AGENT_NAME="DC01"
net start WazuhSvc
```

To make Wazuh **collect the Sysmon channel**, add this to the agent's
`C:\Program Files (x86)\ossec-agent\ossec.conf` inside `<ossec_config>`, then restart
the service:
```xml
<localfile>
  <location>Microsoft-Windows-Sysmon/Operational</location>
  <log_format>eventchannel</log_format>
</localfile>
```
```powershell
Restart-Service WazuhSvc
```

### Ubuntu (UB01, WAZUH01 self, and Kali optionally)
```bash
curl -sO https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.9.0-1_amd64.deb
sudo WAZUH_MANAGER="10.10.10.50" WAZUH_AGENT_NAME="UB01" dpkg -i ./wazuh-agent_4.9.0-1_amd64.deb
sudo systemctl enable --now wazuh-agent
```

## Part C — Confirm every host is reporting
On the dashboard (**Agents** view) all installed agents should show **Active**.
From the manager container you can also check:
```bash
docker exec -it wazuh-lab-wazuh.manager-1 /var/ossec/bin/agent_control -l
```

## Part D — Prove Sysmon + Windows events are flowing
1. On WS01, run something benign (e.g. `whoami /all`, open `cmd.exe`).
2. In the dashboard **Discover / Threat Hunting**, filter `agent.name: WS01` and
   look for `data.win.system.channel: "Microsoft-Windows-Sysmon/Operational"`.
3. Seeing Sysmon event ID **1** for the process you launched = end-to-end success.

Record the results in **[../docs/verification.md](../docs/verification.md)** with
screenshots.

**Snapshot** each host as `configured` once agents report Active.

➡️ Next: **[05-linux-victims.md](05-linux-victims.md)**
