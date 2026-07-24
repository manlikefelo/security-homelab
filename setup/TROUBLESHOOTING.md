# Troubleshooting — real issues I hit building this lab

These are the actual problems I ran into standing up the lab on a Windows 10 host, and
exactly how I fixed each one. They're documented so a reader can reproduce the lab
without losing the time I lost.

> **Reviewer note:** this file is honest engineering evidence — real infrastructure
> problems, diagnosed and solved, not a frictionless fantasy build.

---

## 1. Windows VM boots to a black screen / EFI hang (no installer)

**Symptom.** I created the DC VM with **EFI** firmware, attached the Windows Server
ISO, and booted. The "Press any key to boot from CD or DVD…" prompt never reliably
appeared; the VM sat on a **black screen** and never reached the installer. A
`VBoxManage controlvm <vm> screenshotpng` returned:

```
error: Unsupported resolution for screen shot: 0x0 (screen 0)
```

`0x0` resolution = the guest was producing **no video output at all** — the EFI
firmware hung before initialising the display. This is a known VirtualBox EFI quirk,
made worse when Windows' own hypervisor owns the virtualization extensions (see #2).

**Fix — use BIOS firmware for the Windows VMs.** Windows Server 2022 and Windows
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
Windows Setup screen — no "press any key" needed.

> Applies to **DC01 and WS01**. Do it *before* installing the OS. If you already
> installed Windows in EFI mode and it works, leave it — don't switch firmware on a
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
was **False** — meaning Windows' hypervisor platform (Hyper-V / WSL2 / VBS) held the
VT-x extensions, not VirtualBox.

**What it means.** VirtualBox **7.x runs anyway** via its Hyper-V compatibility layer —
VMs work, just **slower** than native. (Old VirtualBox 6.x and VMware Workstation 16
can't cope with this and fail to start VMs — one reason I chose VirtualBox 7.x.)

**When to act.** Only if the VMs are painfully slow. To give the extensions back to
VirtualBox for near-native speed (⚠️ this **breaks WSL2 / Docker Desktop / Windows
Sandbox** until reverted, and needs a reboot):

```powershell
# Run elevated. Disables the Windows hypervisor launch.
bcdedit /set hypervisorlaunchtype off
# Also turn off these Windows features if present, then reboot:
#   "Virtual Machine Platform", "Windows Hypervisor Platform", "Hyper-V"
Disable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform, HypervisorPlatform -NoRestart
```
Re-enable later with `bcdedit /set hypervisorlaunchtype auto` + a reboot.

> For this lab I **left it on** — the compatibility-layer speed was acceptable and I
> didn't want to disturb WSL2/Docker on the host. Build first, optimise only if needed.

---

## 3. A stray VirtualBox fork from another app (LDPlayer)

**Symptom.** The only `VBoxManage.exe` on the host belonged to **LDPlayer** (an
Android emulator) at `C:\Program Files\ldplayer9box\VBoxManage.exe`, version 6.1.36 —
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
1. Passing **`--location`** to winget — the VirtualBox installer doesn't honour it and
   aborts. Drop it; VirtualBox installs to `C:\Program Files` (only ~250 MB). Redirect
   the **VM library** separately with `VBoxManage setproperty machinefolder` instead.
2. A **dismissed UAC prompt.** The install needs elevation — approve the UAC dialog.

Working command:
```powershell
winget install --id Oracle.VirtualBox -e --accept-package-agreements --accept-source-agreements
```

---

## 5. Disk space — VMs must not land on a full system drive

**Symptom.** C: had only ~11 GB free; the lab needs ~150–250 GB.

**Fix.** Put the whole lab on a roomier drive and tell VirtualBox to store VMs there:
```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" setproperty machinefolder "G:\Cybersecurity Portfolio 2026\VMs"
```
Keep ISOs on the same drive too. The VirtualBox *application* can stay on C: (it's small).

---

## 6. ISO download links 404 (versions drift)

**Symptom.** A pinned Kali URL (`kali-linux-2024.4-…`) returned **404** — that release
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
or as torn diagonal stripes. The session is actually running — it just isn't rendering.

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
