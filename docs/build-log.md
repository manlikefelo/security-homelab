# Build log

A dated record of actually standing up this lab on my host — what I built, what I
verified, and the real issues I hit. This is the honest companion to the aspirational
[verification.md](verification.md) checklist: everything ticked here I ran and
confirmed myself.

> **Reviewer note:** this log shows the lab isn't just documentation — I built it,
> hit real infrastructure problems, and solved them. See
> [../setup/TROUBLESHOOTING.md](../setup/TROUBLESHOOTING.md) for the fixes.

---

## Host & hypervisor
- Host: Windows 10 Pro, 16 GB RAM.
- Hypervisor: **Oracle VirtualBox 7.2.12** (installed via winget after removing a
  conflicting VirtualBox fork bundled with LDPlayer — see TROUBLESHOOTING #3).
- VM library + ISOs on a dedicated drive (`G:`), keeping the full C: drive clear.
- Isolated lab network: host-only adapter re-addressed to **`10.10.10.1/24`**, DHCP
  disabled (guests use static IPs).

## VM shells (all created, budgets per architecture.md)
| VM | RAM | vCPU | Disk | Firmware |
|----|-----|------|------|----------|
| DC01 | 4 GB | 2 | 50 GB | BIOS* |
| WS01 | 4 GB | 2 | 50 GB | (tbd) |
| UB01 | 2 GB | 1 | 20 GB | — |
| KALI01 | 4 GB | 2 | 50 GB | — |
| WAZUH01 | 6 GB | 2 | 50 GB | — |

\* Switched DC01 from EFI → BIOS after an EFI black-screen boot hang under the
Hyper-V compatibility layer (TROUBLESHOOTING #1).

## ISOs downloaded (exact versions)
- `SERVER_EVAL_x64FRE_en-us.iso` (Windows Server 2022, 4.7 GB) — MS Eval Center.
- `ubuntu-22.04.5-live-server-amd64.iso` (2.0 GB).
- `kali-linux-2026.2-installer-amd64.iso` (4.5 GB).

---

## ✅ DC01 — Domain Controller (BUILT & VERIFIED)

- [x] Windows Server 2022 installed (Standard, Desktop Experience), Guest Additions
      installed.
- [x] Static IP **10.10.10.10/24** on the host-only adapter, DNS → self (127.0.0.1).
- [x] Renamed to **DC01**.
- [x] Promoted to first DC of forest **`lab.local`** (NetBIOS `LAB`), AD DS + DNS.
- [x] Verified with `Get-ADDomain` / `Get-ADForest`:
      - Domain `lab.local`, NetBIOS `LAB`, mode Windows2016.
      - PDC emulator `DC01.lab.local`.
      - Services **NTDS, DNS, KDC, Netlogon** all Running.
      - **SYSVOL** and **NETLOGON** shares present (AD healthy).

### Identity seeded (10 users, 8 groups, OUs)
`OU=LAB` → Users / Groups / ServiceAccounts / Workstations. Groups: IT-Admins,
IT-Helpdesk, Finance, HR, Sales, Engineering, Executives, FileShare-RW.

Passwords use a **hybrid scheme** (deliberately weak, varied) so both password-spraying
*and* offline-cracking demos work:
- 3 accounts share one weak password (spray target).
- Several individually weak (crack target).
- `b.otieno` trivially weak — it's the AS-REP/DCSync pivot account.

### Intentional misconfigurations injected & verified
- [x] **#1 Kerberoasting** — `svc_sql` with SPN `MSSQLSvc/dc01.lab.local:1433`.
- [x] **#2 AS-REP roasting** — `b.otieno` `DoesNotRequirePreAuth = True`.
- [x] **#3 DCSync** — `b.otieno` granted replication rights on the domain root.
- [x] **#4 Priv-esc path** — `b.otieno` added to Domain Admins.

### Snapshot
- [x] `configured-dc-with-misconfigs` — clean pre-attack state to revert to before
      each red-team run.

---

## ⬜ Remaining
- [ ] KALI01 — install, DNS → DC, run Project 01 (Kerberoasting) to prove the attack.
- [ ] WAZUH01 — Ubuntu + Wazuh single-node SIEM.
- [ ] WS01 — domain-joined Windows workstation + Sysmon + agent.
- [ ] UB01 — Docker victim containers.
- [ ] End-to-end detection: attack → Wazuh alert.
