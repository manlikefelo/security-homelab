# Build log

A dated record of actually standing up this lab on my host. What I built, what I
verified, and the real issues I hit. This is the record behind the
[verification.md](verification.md) checklist: everything ticked here I ran and
confirmed myself.

> **Note:** I built this lab myself,
> hit real infrastructure problems, and solved them. See
> [../setup/TROUBLESHOOTING.md](../setup/TROUBLESHOOTING.md) for the fixes.

---

## Host & hypervisor
- Host: Windows 10 Pro, 16 GB RAM.
- Hypervisor: **Oracle VirtualBox 7.2.12** (installed via winget after removing a
  conflicting VirtualBox fork bundled with LDPlayer, see TROUBLESHOOTING #3).
- VM library + ISOs on a dedicated drive (`G:`), keeping the full C: drive clear.
- Isolated lab network: host-only adapter re-addressed to **`10.10.10.1/24`**, DHCP
  disabled (guests use static IPs).

## VM shells (all created, budgets per architecture.md)
| VM | RAM | vCPU | Disk | Firmware |
|----|-----|------|------|----------|
| DC01 | 4 GB | 2 | 50 GB | BIOS* |
| WS01 | 4 GB | 2 | 50 GB | EFI† |
| UB01 | 2 GB | 1 | 20 GB | BIOS |
| KALI01 | 4 GB | 2 | 50 GB | BIOS |
| WAZUH01 | 6 GB | 2 | 50 GB | BIOS |

\* Switched DC01 from EFI to BIOS after an EFI black-screen boot hang under the
Hyper-V compatibility layer (TROUBLESHOOTING #1). The Linux VMs (UB01, KALI01,
WAZUH01) use BIOS for the same reason.
† WS01 is the exception: the **Win11 25H2 Enterprise Eval** build boots EFI cleanly
on this host (vTPM 2.0 + Secure Boot), so it runs UEFI where the older images could not.

## ISOs downloaded (exact versions)
- `SERVER_EVAL_x64FRE_en-us.iso` (Windows Server 2022, 4.7 GB): MS Eval Center.
- `ubuntu-22.04.5-live-server-amd64.iso` (2.0 GB).
- `kali-linux-2026.2-installer-amd64.iso` (4.5 GB).

---

## DC01: Domain Controller (BUILT & VERIFIED)

- [x] Windows Server 2022 installed (Standard, Desktop Experience), Guest Additions
      installed.
- [x] Static IP **10.10.10.10/24** on the host-only adapter, DNS set to self (127.0.0.1).
- [x] Renamed to **DC01**.
- [x] Promoted to first DC of forest **`lab.local`** (NetBIOS `LAB`), AD DS + DNS.
- [x] Verified with `Get-ADDomain` / `Get-ADForest`:
      - Domain `lab.local`, NetBIOS `LAB`, mode Windows2016.
      - PDC emulator `DC01.lab.local`.
      - Services **NTDS, DNS, KDC, Netlogon** all Running.
      - **SYSVOL** and **NETLOGON** shares present (AD healthy).

### Identity seeded (10 users, 8 groups, OUs)
`OU=LAB` containing Users / Groups / ServiceAccounts / Workstations. Groups: IT-Admins,
IT-Helpdesk, Finance, HR, Sales, Engineering, Executives, FileShare-RW.

Passwords use a **hybrid scheme** (deliberately weak, varied) so both password-spraying
*and* offline-cracking demos work:
- 3 accounts share one weak password (spray target).
- Several individually weak (crack target).
- `b.otieno` trivially weak. It's the AS-REP/DCSync pivot account.

### Intentional misconfigurations injected & verified
- [x] **#1 Kerberoasting**: `svc_sql` with SPN `MSSQLSvc/dc01.lab.local:1433`.
- [x] **#2 AS-REP roasting**: `b.otieno` `DoesNotRequirePreAuth = True`.
- [x] **#3 DCSync**: `b.otieno` granted replication rights on the domain root.
- [x] **#4 Priv-esc path**: `b.otieno` added to Domain Admins.

### Snapshot
- [x] `configured-dc-with-misconfigs`: clean pre-attack state to revert to before
      each red-team run.

---

## 2026-07-24: KALI01 online + Project 01 (Kerberoasting) proven

### Attacker box configured
Kali 2026.2, login `felix`. Driven headless from the host via VBox `guestcontrol`
(the GUI GDM greeter renders black under VirtualBox: a cosmetic display glitch;
irrelevant since I run everything by copying scripts in and executing them).

Networking via NetworkManager (`nmcli`), both profiles set to autoconnect:
- **eth0 = NAT**: DHCP `10.0.2.15`, default route, internet for apt/docker.
- **eth1 = host-only**: static **`10.10.10.40/24`**, DNS `10.10.10.10`, `never-default`.

Verified from Kali: pings DC01, `nslookup dc01.lab.local` returns 10.10.10.10, and public
internet reachable. Tooling shipped with Kali (no install needed): `impacket-GetUserSPNs`,
`john` (krb5tgs), `hashcat v7.1.2`, `netexec`.

### Project 01: Kerberoasting run end-to-end
As low-priv user `a.mokaya`, `impacket-GetUserSPNs ... -request` pulled the TGS
(RC4/etype 23) for `svc_sql`. Cracked offline: **`svc_sql : P@ssw0rd`** in <1s.
Full record + evidence: [`../../ad-attack-chain/engagement/01-kerberoasting/RUN-LOG.md`](https://github.com/manlikefelo/ad-attack-chain/blob/main/engagement/01-kerberoasting/RUN-LOG.md).

**Real issue hit:** hashcat found no compute backend (`CL_PLATFORM_NOT_FOUND_KHR`):
GPU-less VM and Kali 2026.2's mirror had no `pocl` (CPU OpenCL) package. Rather than
fake the canonical `hashcat -m 13100`, I cracked the identical hash with **John the
Ripper** on CPU. Documented in the run log.

### Snapshots
- [x] `clean-install`: fresh Kali before any lab config.
- [x] `configured-attacker`: net + tooling + Project 01 complete. Revert here to
      re-run attacks from a known-good attacker state.

---

## 2026-07-25: WAZUH01 online: single-node Wazuh SIEM up (blue side live)

### Stack brought up and verified
WAZUH01 (Ubuntu Server 22.04.5, `10.10.10.50`) now runs the full single-node Wazuh
**4.9.0** stack under docker compose, indexer + manager + dashboard, all healthy:

- **Indexer** (`:9200`): cluster status **green**, 1 node, 11/11 shards active (100%).
- **Manager** (`:55000` API, `:1514`/`:1515` agents, `:514/udp` syslog): API
  authenticates and reports `Wazuh v4.9.0 server`.
- **Dashboard** (`:443` → 5601): serves the Wazuh login app (`/app/login`, HTTP 200),
  reachable from the host at **`https://10.10.10.50`**.

Full transcript: [`../setup/evidence/wazuh01-stack-verification.txt`](../setup/evidence/wazuh01-stack-verification.txt).

Networking is dual-homed as designed: **enp0s3 = NAT** (`10.0.2.15`, for image pulls)
and **enp0s8 = host-only** (`10.10.10.50`, isolated lab, DNS pointing at DC01). The stack has a
`restart` policy so it comes back on its own after a reboot.

### Deviations from setup/03
- The running deployment is the upstream Wazuh **single-node compose** layout
  (project at `~/wazuh2`), so it currently ships the stock demo credentials inline and
  publishes the dashboard on **443** rather than the `.env`-driven `:5601` design in
  [../setup/03-wazuh-siem.md](../setup/03-wazuh-siem.md). Fine for an **isolated,
  host-only lab**, flagged to harden (move creds to `.env`, rotate passwords) before
  this pattern goes anywhere near a routable network.
- OpenSearch heap is trimmed to **768 MB** (`-Xms768m -Xmx768m`) to fit alongside the
  other VMs on a 16 GB host.

### Real issues hit (see TROUBLESHOOTING.md)
- **Host RAM contention wedged the guest.** With DC01 (4 GB) *and* WAZUH01 (6 GB) both
  running, the host had only ~4 GB free; WAZUH01 thrashed into an unresponsive state,
  sshd accepted TCP but never sent a banner, and the guest ignored ACPI shutdown. Fix:
  saved DC01's state to free its RAM, then cold-booted WAZUH01 clean. It came up
  healthy with ~5.3 GB free and no swap in use. Confirms the phased/low-RAM operating
  model: the indexer needs its memory to even start.
- **Adapter drift.** WAZUH01's NAT nic had been left as *bridged*; reset nic1 to NAT and
  re-added the `127.0.0.1:2222 → :22` SSH port-forward used to drive the box headless
  (its server console framebuffer freezes after early boot, cosmetic).

---

## 2026-07-25 (cont.): DC01 agent enrolled + Kerberoast DETECTED (red→blue loop closed)

Installed the **Wazuh agent 4.9.0 on DC01** pointing at the manager (`10.10.10.50`);
it enrolled ("Valid key received" → "Agent is now online") and shows **Active** (id
001) via `agent_control -l`. Set the service to Automatic so it survives reboots.

Loaded custom rule **100010** into the manager (`/var/ossec/etc/rules/local_rules.xml`)
and restarted it. DC01 already audits *Kerberos Service Ticket Operations*, so TGS
requests generate **Event 4769**.

Re-ran **Project 01 Kerberoasting** with all three VMs up (DC01 + KALI01 + WAZUH01).
The `GetUserSPNs` request from KALI01 produced a 4769/RC4 event on DC01 → the agent
shipped it → **rule 100010 fired**. In the dashboard, `rule.id:100010` returns 1 hit
with the right fields (eventID 4769, ticketEncryptionType 0x17, serviceName svc_sql,
source `10.10.10.40`). Full record + dashboard screenshots:
[`../../ad-attack-chain/engagement/01-kerberoasting/RUN-LOG.md`](https://github.com/manlikefelo/ad-attack-chain/blob/main/engagement/01-kerberoasting/RUN-LOG.md).

**Issues hit / notes:**
- The agent's Sysmon eventchannel subscription errors `15007` until Sysmon is
  installed on DC01 (guide 04 Part A), irrelevant to this detection, which uses the
  Security log.
- The fresh dashboard had **no index pattern**, so Discover was empty; created
  `wazuh-alerts-*` (time field `timestamp`) and set it default before alerts rendered.
- 3-VM RAM squeeze on the 16 GB host: trimmed KALI01 to 2 GB for the attack run so all
  three fit without thrashing.

---

## 2026-07-26: WS01 built: Win11 client domain-joined + Sysmon + Wazuh agent (Active)

Stood up **WS01**, the domain-joined Windows workstation.

- **OS:** installed **Windows 11 25H2 Enterprise Evaluation** (build 26100, free 90-day,
  no key), downloaded via the Microsoft Evaluation Center fwlink. Surprise win:
  **EFI boots fine on this Win11 build** (my earlier VMs went BIOS because EFI
  black-screened), so WS01 runs EFI + vTPM 2.0 and needed no TPM-bypass. Boot the ISO
  from the UEFI **Boot Manager**: the "press any key to boot from CD" prompt times out
  faster than host scancode injection can catch it.
- **Identity/network:** renamed the OOBE-generated `DESKTOP-HKAKI8M` to **WS01**; local
  admin is `workstation 1` (has a space). Ethernet = NAT DHCP (internet), Ethernet 2 =
  host-only static **10.10.10.20/24**, DNS **10.10.10.10**.
- **Domain join:** joined **lab.local** and verified `PartOfDomain=True` +
  `Test-ComputerSecureChannel = True`. The logon screen now shows the domain
  "Other user" tile.
- **Telemetry:** installed **Sysmon** (SwiftOnSecurity config, `scripts/sysmon/`), config
  validated, service Running, logging Event ID 1. Installed the **Wazuh agent 4.9.0**
  pointing at the manager `10.10.10.50`, added the Sysmon eventchannel to `ossec.conf`.
  It enrolled as **ID 002** and the manager reports it **Active** with its real OS
  string + live keep-alive, so it's actively reporting.

**Issues hit / notes:**
- **Driving Win11 headless is the hard part.** VBox guestcontrol runs *non-elevated*
  and Win11's UAC uses the secure desktop, which can't be clicked/keyboarded from the
  host. Fix: one interactive admin run of `C:\lab\netconfig.ps1` that set the IP,
  renamed the box, **and set `EnableLUA=0`**, after the reboot guestcontrol gets a full
  admin token, so all later steps (join, Sysmon, agent) ran hands-off.
- **RAM squeeze (the recurring one):** DC01(4)+WS01(4)+WAZUH01(6) on a 16 GB host pinned
  free RAM to ~1.8 GB and **WAZUH01 thrashed**, sshd accepted TCP but never sent a
  banner and Docker stalled. Powered DC01 off (it isn't needed to verify a Windows
  agent, only the target host + WAZUH01 are), freed 4 GB, reset WAZUH01, and the stack
  came up clean. Verified enrollment via SSH over the `127.0.0.1:2222` NAT forward.
- Agent showed registered (`client.keys` had `002 WS01`) but wasn't in `agent_control -l`
  until I **restarted `WazuhSvc`** so it reconnected to the freshly-recovered manager.

Evidence: [`../setup/evidence/ws01/`](../setup/evidence/ws01/) (EFI boot, installer,
joined logon screen, `agent_control` Active list + WS01 agent detail).

---

## 2026-07-30: UB01 built: Linux victim box + Docker victims + Wazuh agent (Active)

Stood up **UB01**, the Linux victim host: the last VM. Per the architecture it runs the
vulnerable Linux services as **Docker containers** rather than extra VMs, to save RAM.

- **OS install:** Ubuntu Server **22.04.5**, static **10.10.10.30/24**, DNS **10.10.10.10**,
  user `felix`. The server console framebuffer freezes right after early boot (same
  cosmetic glitch as WAZUH01), so the interactive Subiquity installer can't be driven by
  screenshot. I switched to an **autoinstall (cloud-init) seed**: a `cidata` ISO with
  `user-data`/`meta-data`, and passed the `autoinstall` kernel arg by blind-typing it
  into GRUB via scancodes. The install then ran unattended and reproducibly.
- **Victims:** installed Docker (29.1.3) + compose v2 and brought up
  [`victims/docker-compose.yml`](../victims/docker-compose.yml): **Juice Shop** (:3000),
  **DVWA** (:8080), and a weak **SSH victim** (:2222). All three verified serving over the
  lab net (HTTP 200 / SSH banner). Snapshot **`configured-victim`**.
- **Telemetry:** installed the **Wazuh agent 4.9.0** (`WAZUH_MANAGER=10.10.10.50`).
  Enrolled and reports **Active** (id **004**). Evidence in
  [`../setup/evidence/ub01/`](../setup/evidence/ub01/).

**Issues hit / notes:**
- **Boot wedges on 1 vCPU.** The first post-install boots hung (kernel `soft lockup:
  CPU#1 stuck`) and the VM got stuck "stopping". Fix: bumped UB01 to **2 vCPU / 3 GB** and
  added PAE + nested paging + IOAPIC. It then boots cleanly.
- **sshd didn't start** on first boot: the removed cidata seed made cloud-init's final
  stage fail, so SSH host keys were never generated. Fix: logged in blind at the tty
  console (scancode typing), ran `ssh-keygen -A` + `systemctl enable --now ssh`, then
  **disabled cloud-init** (`/etc/cloud/cloud-init.disabled`) so it's stable across reboots.
- **Agent enrolled but stuck "Unknown" (`Last keep alive: null`).** The manager held a
  stale registration whose key didn't match the agent's, so keep-alives were silently
  rejected. Fix: removed the stale agent on the manager (`manage_agents -r`) and
  re-enrolled fresh via `agent-auth`, giving a new matching key, agent went **Active** (new id 004).
- **`sudo` on WAZUH01 needs a password** (felix isn't NOPASSWD there, unlike UB01), so
  headless `sudo docker …` calls hung on the invisible password prompt until I switched to
  `sudo -S` with the password piped in. Not a fault: a driving gotcha worth recording.
- **RAM phasing held:** the agent-verify phase ran **UB01 + WAZUH01 only** (DC01/WS01 off).
  Even so, UB01(3)+WAZUH01(6) pins free host RAM to ~2 GB, fine for verification but not
  a phase to leave running.

---

## 2026-07-31: UB01 re-verified after the repo split; agent needs re-enroll

Powered UB01 back up from the `configured-victim` snapshot to confirm it's ready for the
web-pentest project. Verified live over SSH (`127.0.0.1:2223`, `felix`):
- **Host-only IP** `10.10.10.30/24` on `enp0s8`, up.
- **Docker victims all serving:** `juice-shop` (:3000 returns HTTP 200), `dvwa`
  (:8080 returns 302 to login), `ssh-victim` (:2222): all `Up`.

**Gotcha found:** the Wazuh agent is **not present on this snapshot** (no `/var/ossec`,
no `wazuh-agent` unit). The agent I enrolled on 2026-07-30 (id 004, Active) was installed
*after* the `configured-victim` snapshot was taken, so restoring that snapshot rolls the
box back to before the agent existed. Not a data-loss issue, the victims are intact, but
UB01's telemetry won't reach Wazuh until the agent is reinstalled. I'll re-enroll it at the
start of the web-pentest project (that's the phase that actually needs UB01's logs in the
SIEM anyway), then re-snapshot so it sticks.

---

## Remaining
- [x] KALI01: installed, DNS pointing at DC, Project 01 (Kerberoasting) proven.
- [x] WAZUH01: Ubuntu + Wazuh single-node SIEM up & verified (4.9.0, indexer green).
- [x] DC01 Wazuh agent enrolled (Active) + Kerberoast detected via rule 100010.
- [x] WS01: Win11 domain-joined workstation + Sysmon + agent **Active**.
- [x] UB01: Ubuntu + Docker victims (Juice Shop/DVWA/SSH) + Wazuh agent **Active** (id 004).
- [ ] Projects 02 (AS-REP) / 03 (DCSync) / 04 (BloodHound), run each attack → Wazuh alert.
