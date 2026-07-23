# 00 — Prerequisites & downloads

Everything here is **free**. Nothing binary is committed to this repo — instead I
list the exact official sources, versions, and where to verify checksums. Follow the
guides in order (`00` → `05`).

> **Reviewer note:** I deliberately keep ISOs and installers *out of git* (see
> [.gitignore](../.gitignore)) and document reproducible download sources instead.
> That keeps the repo small, legal, and reproducible.

---

## Host requirements

- **VirtualBox** (free, GPLv2) + the VirtualBox Extension Pack (free for personal use).
  <https://www.virtualbox.org/wiki/Downloads> — verify the SHA-256 published on that
  page against your download.
- 16 GB RAM, ~250 GB free disk, virtualization (VT-x/AMD-V) enabled in BIOS.
- The host in this repo is **Windows 10 Pro**; all host-side automation is PowerShell.

## Guest images (all free)

| Guest | Source | Notes |
|-------|--------|-------|
| **Windows Server 2022** (DC01) | Microsoft Evaluation Center | 180-day eval, no license key needed |
| **Windows 10 / 11 Enterprise** (WS01) | Microsoft Evaluation Center | 90-day eval |
| **Ubuntu Server 22.04 LTS** (UB01, WAZUH01) | ubuntu.com/download/server | LTS |
| **Kali Linux** (KALI01) | kali.org/get-kali (VirtualBox image) | Pre-built VBox image saves setup |

> Microsoft Eval Center URLs change over time — search
> "Windows Server 2022 evaluation ISO" and "Windows 10/11 Enterprise evaluation" on
> `microsoft.com`. Record the exact ISO filename + SHA-256 you downloaded in
> `setup/DOWNLOADS.local` (gitignored) for your own reproducibility.

## Reused config sources (referenced, not committed)

- **Sysmon** — from Sysinternals: <https://learn.microsoft.com/sysinternals/downloads/sysmon>
- **SwiftOnSecurity sysmon-config** — <https://github.com/SwiftOnSecurity/sysmon-config>
  (I reference it; [../scripts/sysmon/](../scripts/sysmon/) fetches it by URL.)
- **Wazuh docker** — <https://github.com/wazuh/wazuh-docker>

---

## Build order

1. **[01-virtualbox-network.md](01-virtualbox-network.md)** — create the isolated
   host-only network and set static IPs.
2. **[02-active-directory.md](02-active-directory.md)** — stand up DC01, run the
   PowerShell scripts to build the domain, users, groups, and misconfigurations.
   Join WS01 to the domain.
3. **[03-wazuh-siem.md](03-wazuh-siem.md)** — bring up the Wazuh single-node stack
   on WAZUH01 via docker-compose.
4. **[04-sysmon-and-agents.md](04-sysmon-and-agents.md)** — install Sysmon (Swift
   config) + Wazuh agents on every host; confirm logs flow.
5. **[05-linux-victims.md](05-linux-victims.md)** — deploy vulnerable Linux victim
   containers on UB01.

Then run the checklist in **[../docs/verification.md](../docs/verification.md)**.
