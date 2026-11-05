# 01: VirtualBox isolated network

Goal: create one **host-only** network (`10.10.10.0/24`) that carries all lab traffic,
isolated from the home LAN. NAT is added per-VM only for build-time downloads and
detached afterwards.

> **Reviewer note:** isolation is a safety control: the lab contains deliberately
> vulnerable machines. Look at how NAT is *detached* before any attack phase.

---

## 1. Create the host-only network

GUI: **File → Tools → Network Manager → Host-only Networks → Create**, then set:
- IPv4 address: `10.10.10.1`, mask `255.255.255.0`
- **Disable the DHCP server** (I use static IPs inside the guests).

Or via CLI (PowerShell on the host):

```powershell
$vbox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
& $vbox hostonlyif create                              # creates e.g. vboxnet0
& $vbox hostonlyif ipconfig "VirtualBox Host-Only Ethernet Adapter" `
        --ip 10.10.10.1 --netmask 255.255.255.0
# Ensure the DHCP server on that iface is off:
& $vbox dhcpserver remove --interface "VirtualBox Host-Only Ethernet Adapter" 2>$null
```

## 2. Per-VM adapters

For **each** VM, in **Settings → Network**:

- **Adapter 1** → *Host-only Adapter* → select the network above. **Always on.**
- **Adapter 2** → *NAT*. **Enable only while building**, then uncheck "Cable
  Connected" (or disable the adapter) before attack/detection phases.

CLI example for DC01:

```powershell
& $vbox modifyvm "DC01" --nic1 hostonly --hostonlyadapter1 "VirtualBox Host-Only Ethernet Adapter"
& $vbox modifyvm "DC01" --nic2 nat                      # build-time internet
# Later, isolate:
& $vbox modifyvm "DC01" --cableconnected2 off           # detach NAT
```

## 3. Static IPs inside each guest

Set these inside the OS (they persist across snapshots/reboots).

### Windows (DC01 / WS01): run in elevated PowerShell
```powershell
# DC01 example - adjust IP per host from the IP scheme table
$ifIndex = (Get-NetAdapter | Where-Object Status -eq 'Up' |
            Where-Object { $_.InterfaceDescription -notmatch 'NAT' }).ifIndex
New-NetIPAddress -InterfaceIndex $ifIndex -IPAddress 10.10.10.10 `
    -PrefixLength 24 | Out-Null
# DC01 points DNS at itself; every other Windows host points at the DC.
Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses 127.0.0.1
```
For **WS01**, use `10.10.10.20` and DNS `10.10.10.10`.

### Ubuntu (UB01 / WAZUH01): netplan
`/etc/netplan/01-lab.yaml` (use the host-only interface name from `ip a`, e.g. `enp0s3`):
```yaml
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: false
      addresses: [10.10.10.30/24]      # WAZUH01 = 10.10.10.50
      nameservers:
        addresses: [10.10.10.10]        # the DC
```
```bash
sudo netplan apply
```

### Kali (KALI01)
Set `10.10.10.40/24`, DNS `10.10.10.10` (via NetworkManager GUI or `/etc/network/interfaces`).
Pointing Kali's DNS at the DC is what lets AD name resolution (`dc01.lab.local`) work
during attacks.

## 4. Verify connectivity

```bash
ping 10.10.10.10        # from each VM, should reach the DC
nslookup dc01.lab.local 10.10.10.10   # once AD DNS is up (guide 02)
```

## 5. IP reference

| Host    | IP           | DNS         |
|---------|--------------|-------------|
| DC01    | 10.10.10.10  | 127.0.0.1   |
| WS01    | 10.10.10.20  | 10.10.10.10 |
| UB01    | 10.10.10.30  | 10.10.10.10 |
| KALI01  | 10.10.10.40  | 10.10.10.10 |
| WAZUH01 | 10.10.10.50  | 10.10.10.10 |

→ Next: **[02-active-directory.md](02-active-directory.md)**
