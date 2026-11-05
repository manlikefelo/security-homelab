# Troubleshooting: real issues I hit building this lab

These are the actual problems I ran into standing up the lab on a Windows 10 host, and
exactly how I fixed each one. They're documented so a reader can reproduce the lab
without losing the time I lost.

> **Note:** these are real infrastructure problems I hit, diagnosed, and solved.

---

## 1. Windows VM boots to a black screen / EFI hang (no installer)

**Symptom.** I created the DC VM with **EFI** firmware, attached the Windows Server
ISO, and booted. The "Press any key to boot from CD or DVD…" prompt never reliably
appeared; the VM sat on a **black screen** and never reached the installer. A
`VBoxManage controlvm <vm> screenshotpng` returned:

```
error: Unsupported resolution for screen shot: 0x0 (screen 0)
```

`0x0` resolution = the guest was producing **no video output at all**: the EFI
firmware hung before initialising the display. This is a known VirtualBox EFI quirk,
made worse when Windows' own hypervisor owns the virtualization extensions (see #2).

**Fix: use BIOS firmware for the Windows VMs.** Windows Server 2022 and Windows
10/11 install fine in BIOS/MBR mode, and VirtualBox's BIOS DVD-boot is far more
reliable than its EFI path. The disk was still blank, so switching cost nothing:

```powershell
$vbm = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
& $vbm controlvm "DC01" poweroff
& $vbm modifyvm  "DC01" --firmware bios
& $vbm modifyvm  "DC01" --ioapic on --vram 64      # I/O APIC required for >1 vCPU
& $vbm modifyvm  "DC01" --boot1 dvd --boot2 disk
& $vbm startvm   "DC01" --type gui
```

After this the VM auto-booted the ISO straight to **"Loading files…"** and the
Windows Setup screen: no "press any key" needed.

> Applies to **DC01 and WS01**. Do it *before* installing the OS. If you already
> installed Windows in EFI mode and it works, leave it, don't switch firmware on a
> disk that already has an OS or it won't boot.

**Verifying video is alive from the host** (handy when you can't tell if it's slow or
truly hung):
```powershell
& $vbm controlvm "DC01" screenshotpng "screen.png"   # 0x0 error = no video = hung
```

---

## 2. Windows' own hypervisor owns virtualization (Hyper-V / VBS coexistence)

**Symptom.** On the host, `(Get-CimInstance Win32_ComputerSystem).HypervisorPresent`
returned **True**, and `(Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled`
was **False**, meaning Windows' hypervisor platform (Hyper-V / WSL2 / VBS) held the
VT-x extensions, not VirtualBox.

**What it means.** VirtualBox **7.x runs anyway** via its Hyper-V compatibility layer:
VMs work, just **slower** than native. (Old VirtualBox 6.x and VMware Workstation 16
can't cope with this and fail to start VMs: one reason I chose VirtualBox 7.x.)

**When to act.** Only if the VMs are painfully slow. To give the extensions back to
VirtualBox for near-native speed (this **breaks WSL2 / Docker Desktop / Windows
Sandbox** until reverted, and needs a reboot):

```powershell
# Run elevated. Disables the Windows hypervisor launch.
bcdedit /set hypervisorlaunchtype off
# Also turn off these Windows features if present, then reboot:
#   "Virtual Machine Platform", "Windows Hypervisor Platform", "Hyper-V"
Disable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform, HypervisorPlatform -NoRestart
```
Re-enable later with `bcdedit /set hypervisorlaunchtype auto` + a reboot.

> For this lab I **left it on**: the compatibility-layer speed was acceptable and I
> didn't want to disturb WSL2/Docker on the host. Build first, optimise only if needed.

---

## 3. A stray VirtualBox fork from another app (LDPlayer)

**Symptom.** The only `VBoxManage.exe` on the host belonged to **LDPlayer** (an
Android emulator) at `C:\Program Files\ldplayer9box\VBoxManage.exe`, version 6.1.36:
a private, modified VirtualBox fork. It **cannot** run standard Windows/Linux guests,
and its drivers can fight the real VirtualBox over the same virtualization hooks.

**Fix.** Uninstall LDPlayer (removing its bundled VBox fork) *before* installing real
Oracle VirtualBox, then confirm no stray binary remains:

```powershell
# after uninstalling LDPlayer, verify the fork is gone:
Get-ChildItem "C:\Program Files" -Filter VBoxManage.exe -Recurse -Depth 3 -EA SilentlyContinue
# should return nothing until real VirtualBox is installed
```

> Any app that bundles VirtualBox (some Android emulators, older Genymotion, etc.) can
> cause this. If VMs mysteriously fail to start, hunt for a second `VBoxManage.exe`.

---

## 4. `winget install Oracle.VirtualBox` fails with exit code 1

**Symptom.** The winget install failed with `Installer failed with exit code: 1`.

**Cause / fix.** Two culprits:
1. Passing **`--location`** to winget: the VirtualBox installer doesn't honour it and
   aborts. Drop it; VirtualBox installs to `C:\Program Files` (only ~250 MB). Redirect
   the **VM library** separately with `VBoxManage setproperty machinefolder` instead.
2. A **dismissed UAC prompt.** The install needs elevation, approve the UAC dialog.

Working command:
```powershell
winget install --id Oracle.VirtualBox -e --accept-package-agreements --accept-source-agreements
```

---

## 5. Disk space: VMs must not land on a full system drive

**Symptom.** C: had only ~11 GB free; the lab needs ~150–250 GB.

**Fix.** Put the whole lab on a roomier drive and tell VirtualBox to store VMs there:
```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" setproperty machinefolder "G:\Cybersecurity Portfolio 2026\VMs"
```
Keep ISOs on the same drive too. The VirtualBox *application* can stay on C: (it's small).

---

## 6. ISO download links 404 (versions drift)

**Symptom.** A pinned Kali URL (`kali-linux-2024.4-…`) returned **404**, that release
had rolled off the mirror.

**Fix.** Use the version-agnostic **`/current/`** path for Kali and the release
directory for Ubuntu, and read the actual filename from the listing:
```powershell
# Kali: /current/ always holds the latest installer
(Invoke-WebRequest "https://cdimage.kali.org/current/" -UseBasicParsing).Content |
  Select-String -Pattern 'kali-linux-[\d.]+-installer-amd64\.iso' -AllMatches |
  ForEach-Object { $_.Matches.Value } | Select-Object -Unique
# Ubuntu: browse https://releases.ubuntu.com/22.04/ for the current 22.04.x point release
```

---

## Kali GNOME desktop renders black / garbled (blank greeter, torn screenshots)

**Symptom.** After installing Kali, the GDM login greeter shows only a black screen
with a cursor, and `VBoxManage controlvm KALI01 screenshotpng` captures come back black
or as torn diagonal stripes. The session is actually running. It just isn't rendering.

**Cause.** The default `vboxsvga` graphics controller with 64 MB VRAM doesn't drive the
Kali GNOME (Wayland) session reliably on this host.

**Fix.** Power the VM off and switch it to **VMSVGA** with **128 MB VRAM**:
```powershell
$vbm = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
& $vbm controlvm KALI01 poweroff              # ensure it's fully off first
& $vbm modifyvm KALI01 --graphicscontroller vmsvga --vram 128 --accelerate3d off
& $vbm startvm  KALI01 --type gui
```
After this the greeter and desktop render cleanly and screenshots are legible. (If the
greeter still looks blank for a second after boot, tap Shift once to wake it.)

---

## WAZUH01 (Ubuntu 22.04 server) build gotchas

**Disk controller: install on IDE, then MOVE THE DISK BACK TO SATA to boot.**
The Debian/Ubuntu *installer* partitioner hangs on SATA/AHCI under this host's
Hyper-V compat layer (same as Kali), so I installed with the disk on an **IDE (PIIX4)**
controller. But the *installed* Ubuntu then **hung in initramfs at "Loading essential
drivers"** because its generic initramfs booted probing AHCI and never found the IDE
root device. Fix: after the install completes, power off and move the .vdi back to
**SATA**: Ubuntu boots fine from SATA at runtime (the partitioner hang is an
installer-only problem). So: **IDE for the install, SATA for running.**
```powershell
$vbm storageattach WAZUH01 --storagectl IDE  --port 0 --device 0 --medium none
$vbm storageattach WAZUH01 --storagectl SATA --port 0 --device 0 --type hdd --medium "<path>.vdi"
```

**Console framebuffer freezes after early boot (headless is fine).**
With Ubuntu server the VBox console screenshot freezes on a boot frame and never
repaints (`vboxvideodrmfb`/`vmwgfx` DRM quirk): the OS is actually up. Don't trust
the frozen screen; verify via the network instead. I drove the box over **SSH**: add a
NAT port-forward and connect to it (no host-only IP needed for the first step).
```powershell
$vbm modifyvm WAZUH01 --natpf1 "ssh,tcp,127.0.0.1,2222,,22"   # then ssh felix@127.0.0.1 -p 2222
```

**apt fails with `file:/cdrom ... no Release file`.** The installer leaves the install
media in apt sources. Comment it out before any apt install:
`sudo sed -i -E 's|^([^#].*/cdrom.*)$|# \1|' /etc/apt/sources.list && sudo apt-get update`.

**`dpkg was interrupted`.** Because I reset the VM past the installer's hung
"downloading security updates" step, package config was left half-done. Finish it once:
`sudo dpkg --configure -a && sudo apt-get -y -f install`.

---

## Wazuh manager comes up but agents stay "Unknown" / connection refused

**Symptom.** After booting WAZUH01, the containers all show `Up`, the host publishes
1514/1515, but DC01's agent log loops `Unable to connect to '[10.10.10.50]:1514/tcp':
... actively refused` and `agent_control -l` inside the manager shows every agent as
**Unknown**. `docker exec ... wazuh-control status` reveals `wazuh-remoted`,
`wazuh-analysisd`, `wazuh-authd` **not running**, and the manager's `ossec.log` is full
of `Unable to connect to socket 'queue/db/wdb' ... Connection refused (111)`.

**Cause.** On this 6 GB (squeezed to 4 GB), memory-thrashing VM, `wazuh-db` (wdb)
occasionally fails to come up cleanly at boot. Because every other daemon
(analysisd/remoted/authd) depends on the wdb socket, they all stay down, so the
host's docker-proxy accepts the agent's TCP SYN but the backend refuses it.

**Fix.** Restart the manager container so init re-runs in order (wdb first):
```bash
sudo docker restart wazuh2-wazuh.manager-1
# wait ~90s, then confirm the daemons and agent:
sudo docker exec wazuh2-wazuh.manager-1 /var/ossec/bin/wazuh-control status | grep -E 'wdb|remoted|analysisd'
sudo docker exec wazuh2-wazuh.manager-1 /var/ossec/bin/agent_control -l
```
The agent reconnects as **Active** within a minute of `remoted` coming up.

---

## Dashboard login rejects the `.env` password (401)

**Symptom.** `admin` + the `INDEXER_PASSWORD` from `wazuh/.env` returns *Invalid
username or password* in the dashboard, and a direct check is 401:
`docker exec ...indexer... curl -k -u admin:<env-pw> https://localhost:9200/ -> 401`.

**Cause.** Editing `INDEXER_PASSWORD` in `.env` does **not** re-hash the password inside
the indexer's OpenSearch security index, that only happens if `securityadmin.sh` is
re-run against the new `internal_users.yml`. If that step was skipped, the indexer is
still running with the **stock demo password `SecretPassword`**.

**Fix (lab).** Log in with `admin` / `SecretPassword`. To actually harden it, set the
hash in `internal_users.yml` and run the securityadmin tool, then restart. (Noted as a
follow-up; the lab is isolated so the demo password is acceptable for now.)

---

## Driving the Kali GNOME (Wayland) GUI headlessly from the host

Useful when capturing dashboard screenshots without a mouse on the host:

- **The GDM greeter renders black to `screenshotpng` until it's fully drawn**: wait
  for `gdm.service` to start, then tap a key once (`keyboardputscancode 39 b9`) and it
  paints. Log in blind: the greeter pre-focuses the password field, so
  `keyboardputstring '<pw>'` + Enter works.
- **Keyboard injection (`keyboardputscancode`/`keyboardputstring`) is reliable**; use it
  for everything: Ctrl+L to focus Firefox's address bar (`1d 26 a6 9d`), typing URLs,
  accepting the self-signed cert (Tab to *Advanced* → Enter, scroll *End*, Tab to
  *Accept the Risk and Continue* → Enter), and filling login forms.
- **Launch Firefox at a URL from the session env** rather than fighting window focus,
  export the running session's `DISPLAY`/`WAYLAND_DISPLAY`/`XAUTHORITY`/
  `DBUS_SESSION_BUS_ADDRESS`/`XDG_RUNTIME_DIR` (read them from
  `/proc/$(pgrep firefox-esr)/environ`) then `firefox --new-window "<url>" &`.
- **Synthetic mouse clicks are the one thing that does NOT work.** `xdotool` clicks
  land on Firefox (it's Xwayland) but GNOME's **RemoteDesktop portal re-prompts for
  consent on every pointer button event** and resets the toggle each time, so you can't
  reliably click page controls (e.g. Discover's per-row "expand document" caret). Drive
  everything you can by keyboard and URL; for detail that would need a click, pull the
  data another way (e.g. the raw alert JSON from
  `/var/ossec/logs/alerts/alerts.json`).
- **`sources.list` after a cdrom install is empty** (only the commented `deb cdrom`
  line), so `apt-get install` reports "Unable to locate package". Add the Kali repo:
  `echo "deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" | sudo tee -a /etc/apt/sources.list && sudo apt-get update`.
  (Same class of issue as the WAZUH01 cdrom-source gotcha above.)

---

## DCSync / enumeration produce NO Wazuh alert: Event 4662 not being logged

**Symptom.** The DCSync (Project 03) and BloodHound-enumeration (Project 04) blue phases
fire nothing: `grep 4662 alerts.json` returns 0, even though the attack clearly ran
and the DC01 agent is Active.

**Cause.** Windows does **not** audit directory object access (Event 4662) by default.
Two things must both be on, on DC01:
1. The *Directory Service Access* audit subcategory (Success).
2. A **SACL on the domain-root object** that audits the replication extended rights.

**Fix.**
```powershell
auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable
```
Then add the SACL. The AD-module path (`Get-Acl "AD:$rootDN" -Audit` → `AddAuditRule` →
`Set-Acl`) works, but it threw `Get-ADDomain : A local error has occurred` when the DC
was memory-starved. The reliable path is raw **ADSI**:
```powershell
$rootDN = ([ADSI]"LDAP://RootDSE").defaultNamingContext
$de = [ADSI]"LDAP://$rootDN"
$de.psbase.Options.SecurityMasks = [System.DirectoryServices.SecurityMasks]::Sacl
$sd  = $de.psbase.ObjectSecurity
$everyone = New-Object System.Security.Principal.SecurityIdentifier(
    [System.Security.Principal.WellKnownSidType]::WorldSid, $null)
foreach ($guid in '1131f6aa-9c07-11d1-f79f-00c04fc2dcd2','1131f6ad-9c07-11d1-f79f-00c04fc2dcd2') {
    $sd.AddAuditRule((New-Object System.DirectoryServices.ActiveDirectoryAuditRule(
        $everyone,'ExtendedRight','Success',[Guid]$guid)))
}
$de.psbase.ObjectSecurity = $sd; $de.psbase.CommitChanges()
```
After this, re-run the DCSync/collection and the 4662s flow → rules 100012 / 100013 fire.

---

## WAZUH01 sshd never sends its banner during 3-VM phases (indexer thrash)

**Symptom.** During a live DC01 + KALI01 + WAZUH01 phase, WAZUH01's SSH (127.0.0.1:2222)
accepts TCP but times out "during banner exchange", even after powering Kali off, and
even after a hard reset. The console framebuffer is frozen (cosmetic) so it looks hung.

**Cause.** At 6 GB the single-node Wazuh indexer's JVM plus the manager/dashboard
containers thrash into swap under the 3-VM memory ceiling, and never recover on their
own, sshd can't get enough CPU/RAM to complete the handshake.

**Fix.**
1. Give WAZUH01 more RAM: `VBoxManage modifyvm WAZUH01 --memory 8192` (VM off first).
   8 GB + DC01 squeezed to 2 GB = 10 GB, comfortably under the 12 GB ceiling.
2. Boot WAZUH01 **alone** (DC01 off too) so the indexer initialises with no contention;
   wait ~4 min, confirm SSH answers and the manager daemons (`wdb`/`remoted`/
   `analysisd`) are up, **then** boot DC01 so its agent reconnects and flushes events.

Never try to bring the whole stack up while another VM is already competing for RAM.

---

## Wazuh Discover shows "Select a datasource" / won't render alert rows

**Symptom.** Navigating Discover by URL (the newer `/app/data-explorer/discover` route)
shows **"Select a datasource"** and spins on *Searching* forever: the `rule.id:…`
query is in the search bar but no hits render, even though the alerts exist in the
index (`curl .../wazuh-alerts-*/_count?q=rule.id:100012` returns a count). The
data-explorer app needs a **mouse click** on the datasource picker, which GNOME's
Wayland RemoteDesktop portal blocks when driving Kali headlessly.

**Fix.** Set the index pattern as **default** server-side, then use the **classic**
Discover route which binds it (no click needed):
```bash
# 1) set wazuh-alerts-* as the default index pattern (id is 'wazuh-alerts')
docker exec wazuh2-wazuh.dashboard-1 curl -s -k -u admin:SecretPassword \
  -X POST "https://localhost:5601/api/opensearch-dashboards/settings/defaultIndex" \
  -H "osd-xsrf: true" -H "Content-Type: application/json" -d '{"value":"wazuh-alerts"}'
```
Then open the **classic** app URL (note `/app/discover`, not `/app/data-explorer/…`):
```
https://10.10.10.50/app/discover#/?_g=(time:(from:now-7d,to:now))&_a=(columns:!(_source),index:'wazuh-alerts',interval:auto,query:(language:kuery,query:'rule.id:100012'),sort:!())
```
Discover then shows `wazuh-alerts-*` selected, the histogram, and the `_source` rows:
the rendered screenshot, no clicks required. This is how the Project 01, 03 and 04
dashboard alert shots were captured.

---

## Quick host-readiness checklist

```powershell
# Real VirtualBox present?
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" --version
# No stray forks?
Get-ChildItem "C:\Program Files" -Filter VBoxManage.exe -Recurse -Depth 3 -EA SilentlyContinue
# Hypervisor coexistence state (informational)?
(Get-CimInstance Win32_ComputerSystem).HypervisorPresent
# Enough space on the VM drive?
Get-Volume | Select DriveLetter, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB)}}
```
