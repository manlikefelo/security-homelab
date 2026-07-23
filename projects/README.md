# Red → Blue projects

Each folder is a self-contained project that **attacks** one of the intentional
misconfigurations from [`../scripts/ad/03-inject-misconfigs.ps1`](../scripts/ad/03-inject-misconfigs.ps1),
then **detects** it in Wazuh. Every project follows the same shape so a reviewer can
compare them quickly:

1. **Scenario** — what the weakness is and why it matters.
2. **Attack (red)** — exact commands from KALI01, with expected output.
3. **Telemetry** — the Windows/Sysmon events the attack generates.
4. **Detection (blue)** — how to see it in Wazuh (query + rule).
5. **Remediation** — how a defender fixes the misconfiguration.
6. **Evidence** — screenshot placeholders proving it worked end-to-end.

> **Reviewer note:** these projects are where the lab pays off — each one closes the
> loop from *offensive action* to *defensive detection* on the same finding. That
> attacker-and-defender symmetry is the skill I'm demonstrating.

| # | Project | Attack | MITRE ATT&CK | Detects with |
|---|---------|--------|--------------|--------------|
| 01 | [Kerberoasting](01-kerberoasting/) | Crack an SPN service account offline | T1558.003 | 4769 RC4 TGS spike |
| 02 | [AS-REP Roasting](02-asrep-roasting/) | Crack a no-preauth user offline | T1558.004 | 4768 preauth-type 0 |
| 03 | [DCSync](03-dcsync/) | Pull hashes via replication rights | T1003.006 | 4662 replication GUIDs |
| 04 | [BloodHound](04-bloodhound/) | Map priv-esc paths in the domain | T1069 / T1087 | 4661/4662 mass LDAP reads |

## Running order
Do them in numeric order. 01–02 need only KALI01 + DC01 (red phase). Detection steps
need WAZUH01 up (blue phase) — see [../docs/low-ram-operating-guide.md](../docs/low-ram-operating-guide.md)
for which VMs to power on.

## Safety
All attacks run **only** on the isolated `10.10.10.0/24` lab network against machines
I built to be vulnerable. The tooling (Impacket, Rubeus, mimikatz, BloodHound) is
standard, publicly documented offensive-security software used here for authorised
learning on my own lab.
