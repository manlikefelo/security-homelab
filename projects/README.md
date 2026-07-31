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

## ATT&CK detection coverage matrix

At-a-glance breadth: which ATT&CK techniques the lab attacks and detects, and the
end-to-end status of each. **Status:** ✅ = attack run **and** detection verified
firing end-to-end · 🟡 = detection rule written, attack not yet run · ⬜ = planned.

| # | Project | Tactic | Technique (ID) | Detection signal | Wazuh rule | Status |
|---|---------|--------|----------------|------------------|------------|--------|
| 01 | [Kerberoasting](01-kerberoasting/) | Credential Access | **T1558.003** — Kerberoasting | Event **4769**, `ticketEncryptionType 0x17` (RC4) | 100010 (lvl 10) | ✅ verified |
| 02 | [AS-REP Roasting](02-asrep-roasting/) | Credential Access | **T1558.004** — AS-REP Roasting | Event **4768**, `preAuthType 0` | 100011 (lvl 10) | ✅ verified |
| 03 | [DCSync](03-dcsync/) | Credential Access | **T1003.006** — DCSync | Event **4662**, replication extended-right GUIDs | 100012 (lvl 12) | 🟡 rule staged |
| 04 | [BloodHound](04-bloodhound/) | Discovery | **T1087.002** — Domain Account Discovery | **4661/4662** read burst (freq ≥15 / 60s) | 100013 (lvl 8) | 🟡 rule staged |

**Completed today (✅):** 2 of 4 techniques attacked and detected end-to-end, both in
the **Credential Access** tactic (Kerberos abuse: T1558.003 + T1558.004). Each closes
the loop on a distinct AD misconfiguration — a Kerberoastable service account and a
pre-auth-disabled Domain Admin. The per-project READMEs (§7) carry the detailed
technique-by-technique matrix and the offline-cracking (T1110.002) sub-steps.

## Running order
Do them in numeric order. 01–02 need only KALI01 + DC01 (red phase). Detection steps
need WAZUH01 up (blue phase) — see [../docs/low-ram-operating-guide.md](../docs/low-ram-operating-guide.md)
for which VMs to power on.

## Safety
All attacks run **only** on the isolated `10.10.10.0/24` lab network against machines
I built to be vulnerable. The tooling (Impacket, Rubeus, mimikatz, BloodHound) is
standard, publicly documented offensive-security software used here for authorised
learning on my own lab.
