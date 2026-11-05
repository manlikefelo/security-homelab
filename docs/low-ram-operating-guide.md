# Low-RAM Operating Guide

**Host: 16 GB RAM. Rule: never exceed ~12 GB of VM RAM at once, leaving ~4 GB for
the host OS + VirtualBox.**

This guide tells me *exactly which VMs to power on* for each phase of a project, and
how to move between phases without losing state. It is the operational companion to
[architecture.md](architecture.md).

> **Reviewer note:** this file is the proof that I designed the lab around a real
> hardware constraint instead of hand-waving it. Each phase has a concrete RAM sum.

---

## RAM allocations at a glance

| VM       | Default RAM | Squeezed RAM | Purpose |
|----------|-------------|--------------|---------|
| DC01     | 4 GB        | **2 GB**     | Active Directory + DNS |
| WS01     | 4 GB        | 2 GB         | Domain workstation (victim) |
| UB01     | 2 GB        | 1 GB         | Docker host for Linux victims |
| KALI01   | 4 GB        | 2 GB         | Attacker |
| WAZUH01  | 6 GB        | 4 GB         | SIEM (memory-hungry, never runs with red VMs unless validating) |

Set RAM in **VirtualBox → VM → Settings → System → Motherboard → Base Memory**, or:

```powershell
# Example: squeeze the DC to 2 GB before a live-detection run
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" modifyvm "DC01" --memory 2048
# Restore afterwards
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" modifyvm "DC01" --memory 4096
```
(VM must be powered off to change base memory.)

---

## Phase 1: RED: attack (Wazuh OFF)

Goal: run exploits/enumeration against a target. The SIEM is **off**: I'm generating
telemetry, not watching it yet.

**Power ON:**

| Non-AD Linux attack | RAM | | AD attack | RAM |
|---------------------|-----|-|-----------|-----|
| KALI01 (4 GB)       |     | | KALI01 (4 GB) | |
| UB01 (2 GB)         |     | | DC01 (4 GB)   | |
|                     |     | | WS01 (4 GB)   | |
| **Total: 6 GB** |     | | **Total: 12 GB** | |

**Power OFF:** WAZUH01 (and any VM not in the row above).

The Windows targets still have Sysmon + Wazuh **agents** installed and logging locally
to disk / the Windows event log during this phase. The agents just can't reach the
manager because WAZUH01 is off. That's fine, the events are captured and I replay/
forward them in the blue phase.

---

## Phase 2: BLUE: detection & replay (targets + Wazuh, Kali OFF)

Goal: bring the SIEM up and confirm the attack telemetry from Phase 1 turns into
alerts. Kali is **off**.

**Power ON:**

| VM       | RAM  |
|----------|------|
| WAZUH01  | 6 GB |
| DC01     | 4 GB |
| WS01 *or* UB01 (whichever I attacked) | 4 / 2 GB |
| **Total** | **~12 GB (WS) / ~10 GB (UB)** |

**Power OFF:** KALI01.

When the agents reconnect to the now-running manager, buffered events flush to Wazuh.
To **replay** attacks against a live SIEM without Kali, I re-run the attack's local
footprint (e.g. re-execute a Kerberoast request from the DC, or `docker` re-trigger a
vulnerable service) and watch the alerts land.

---

## Phase 3: LIVE-DETECTION validation (DC + Wazuh + Kali, DC squeezed to 2 GB)

Goal: the money shot, attacker, SIEM, and DC all live at once, so an attack from Kali
produces a Wazuh alert **in real time**. This is the tightest phase.

**Power ON (in this order):**

| VM       | RAM  | Notes |
|----------|------|-------|
| DC01     | **2 GB** | squeezed, see command above |
| WAZUH01  | 6 GB | needs full memory for the indexer |
| KALI01   | 4 GB | attacker |
| **Total** | **12 GB** | at the ceiling, close other host apps |

**Power OFF:** WS01, UB01.

Because WS01 is off, target AD attacks (Kerberoasting, AS-REP roasting, DCSync
attempts, LDAP enumeration) directly at DC01 from Kali, and confirm the alert appears
on the Wazuh dashboard while the attack is running.

> Before this phase: close browsers/Slack/etc. on the host. 12 GB of VMs + 4 GB host
> is the whole 16 GB. There is no slack.

---

## Snapshots: shut down between sessions without losing state

I snapshot **every VM in a clean, configured state** so I can power everything off
between sessions and restore exact state later.

### Recommended snapshot points
1. `base-installed`: OS installed, static IP set, NAT still attached.
2. `configured`: domain joined / Docker up / agents + Sysmon installed, NAT detached.
3. `pre-attack-clean`: the state I revert to before each fresh red-team run.

### Take a snapshot
```powershell
$vbox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
& $vbox snapshot "DC01"    take "configured" --description "AD+DNS up, agents installed"
& $vbox snapshot "WS01"    take "configured"
& $vbox snapshot "WAZUH01" take "configured"
```

### Restore before a fresh run
```powershell
& $vbox controlvm "DC01" poweroff        # if running
& $vbox snapshot  "DC01" restore "pre-attack-clean"
```

### Save state instead of full shutdown (fast resume, keeps RAM image)
```powershell
& $vbox controlvm "WAZUH01" savestate     # freezes to disk; restores in seconds
```
`savestate` writes the RAM to disk so nothing is lost and startup is quick, ideal for
pausing a phase. Use full `poweroff` + snapshot-restore when I want a *clean* slate.

---

## Quick decision table

| I want to… | Power ON | Power OFF | ≈RAM |
|------------|----------|-----------|------|
| Exploit a Linux victim | KALI01, UB01 | rest | 6 GB |
| Attack Active Directory | KALI01, DC01, WS01 | WAZUH01, UB01 | 12 GB |
| Build detections / replay | WAZUH01, DC01, target | KALI01 | 10–12 GB |
| Prove real-time detection | DC01 (2 GB), WAZUH01, KALI01 | WS01, UB01 | 12 GB |
| Pause for the day | savestate all: | - | 0 |
