# 00: Prerequisites & downloads

Everything here is **free**. Nothing binary is committed to this repo, instead I
list the exact official sources, versions, and where to verify checksums. Follow the
guides in order (`00` → `05`).

> **Reviewer note:** I deliberately keep ISOs and installers *out of git* (see
> [.gitignore](../.gitignore)) and document reproducible download sources instead.
> That keeps the repo small, legal, and reproducible.

---

## Host requirements

- **VirtualBox** (free, GPLv2) + the VirtualBox Extension Pack (free for personal use).
  <https://www.virtualbox.org/wiki/Downloads>, verify the SHA-256 published on that
  page against your download. On Windows you can install it in one line with winget:
  ```powershell
  winget install --id Oracle.VirtualBox -e --accept-package-agreements --accept-source-agreements
  ```
  > I built this lab on **VirtualBox 7.2.12**. The Extension Pack is optional for a
  > host-only lab (it adds USB2/3 + a couple of niceties we don't need), so I skipped it.
- 16 GB RAM, ~250 GB free disk, virtualization (VT-x/AMD-V) enabled in BIOS.
- The host in this repo is **Windows 10 Pro**; all host-side automation is PowerShell.
- **Point VirtualBox's VM library at a roomy drive** before creating VMs: the app
  installs to `C:\Program Files` but VMs are large and should not land on a full C::
  ```powershell
  & "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" setproperty machinefolder "D:\path\to\VMs"
  ```

## Guest images (all free)

These are the **exact versions I used**. Versions drift over time, when a link 404s,
grab the current point release from the same source and update
`setup/DOWNLOADS.local` (gitignored).

| Guest | Version I used | Source | Notes |
|-------|----------------|--------|-------|
| **Windows Server 2022** (DC01) | `SERVER_EVAL_x64FRE_en-us.iso` (4.7 GB) | [MS Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022) | 180-day eval, **no key**. Pick **Standard (Desktop Experience)** at install |
| **Windows 10 / 11 Enterprise** (WS01) | Enterprise eval | [MS Evaluation Center](https://www.microsoft.com/en-us/evalcenter/) | 90-day eval |
| **Ubuntu Server 22.04 LTS** (UB01, WAZUH01) | `ubuntu-22.04.5-live-server-amd64.iso` (2.0 GB) | <https://releases.ubuntu.com/22.04/> | direct, no login |
| **Kali Linux** (KALI01) | `kali-linux-2026.2-installer-amd64.iso` (4.5 GB) | <https://cdimage.kali.org/current/> | full-installer ISO; `/current/` always holds the latest |

> **The Kali/Ubuntu ISOs download directly with no form**: I fetched them in the
> background while the Windows Server VM installed:
> ```powershell
> $dst = "G:\...\ISOs"
> Start-BitsTransfer -Asynchronous -Source "https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso" -Destination "$dst\ubuntu.iso"
> Start-BitsTransfer -Asynchronous -Source "https://cdimage.kali.org/current/kali-linux-2026.2-installer-amd64.iso" -Destination "$dst\kali.iso"
> ```
> Only the Microsoft images need the eval-center form.

> **Before you start, read [TROUBLESHOOTING.md](TROUBLESHOOTING.md)**. It covers the
> real issues I hit (an EFI black-screen boot hang, the Hyper-V/VirtualBox coexistence,
> LDPlayer's conflicting VirtualBox fork) and the fixes, so you don't lose time on them.

## Reused config sources (referenced, not committed)

- **Sysmon**: from Sysinternals: <https://learn.microsoft.com/sysinternals/downloads/sysmon>
- **SwiftOnSecurity sysmon-config**: <https://github.com/SwiftOnSecurity/sysmon-config>
  (I reference it; [../scripts/sysmon/](../scripts/sysmon/) fetches it by URL.)
- **Wazuh docker**: <https://github.com/wazuh/wazuh-docker>

---

## Build order

1. **[01-virtualbox-network.md](01-virtualbox-network.md)**: create the isolated
   host-only network and set static IPs.
2. **[02-active-directory.md](02-active-directory.md)**: stand up DC01, run the
   PowerShell scripts to build the domain, users, groups, and misconfigurations.
   Join WS01 to the domain.
3. **[03-wazuh-siem.md](03-wazuh-siem.md)**: bring up the Wazuh single-node stack
   on WAZUH01 via docker-compose.
4. **[04-sysmon-and-agents.md](04-sysmon-and-agents.md)**: install Sysmon (Swift
   config) + Wazuh agents on every host; confirm logs flow.
5. **[05-linux-victims.md](05-linux-victims.md)**: deploy vulnerable Linux victim
   containers on UB01.

Then run the checklist in **[../docs/verification.md](../docs/verification.md)**.

**Stuck?** See **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** for the real build issues I
hit and their fixes (EFI black-screen boot hang, Hyper-V coexistence, stray VirtualBox
forks, winget failures, disk space, ISO 404s).
