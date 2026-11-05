# Repo guide

Here's the fastest route through this repo and what each stop shows.

---

### 1. The design
1. **[architecture.md](architecture.md)**: read the mermaid diagram and the
   **phase-budget table**. The whole lab is engineered to run a full AD + SIEM
   detection environment on a **16 GB laptop** by never running the red VMs and the
   SIEM at once.
   *Shows:* I design around real hardware constraints and can justify the trade-offs.
2. **[low-ram-operating-guide.md](low-ram-operating-guide.md)**: skim the three phase
   tables; each sums to ≤12 GB.
   *Shows:* operational thinking, not just a wiring diagram.

### 2. The security depth
3. **[../scripts/ad/03-inject-misconfigs.ps1](../scripts/ad/03-inject-misconfigs.ps1)**:
   this is the file to read. Each intentional misconfiguration (Kerberoastable
   service account, AS-REP roastable user, DCSync-over-permission, Domain Admins
   nesting) has a **WHY** comment covering the attack (with MITRE ATT&CK IDs) **and**
   the defender's detection angle.
   *Shows:* I understand offense and defense of the *same* finding, and I can
   automate it idempotently and secret-free.

### 3. The proof it works
4. **[verification.md](verification.md)**: the checklist ending in a live
   Kerberoast → Wazuh alert.
   *Shows:* the attack → log → detect pipeline actually closes.
5. **[ad-attack-chain: Phase 01 RUN-LOG](https://github.com/manlikefelo/ad-attack-chain/blob/main/engagement/01-kerberoasting/RUN-LOG.md)**:
   the actual command output and
   dashboard screenshots of the attack running and the matching Wazuh alert firing.
   The [ad-attack-chain](https://github.com/manlikefelo/ad-attack-chain) repo gives the same red→blue treatment
   to AS-REP roasting, DCSync and BloodHound, each with its own custom detection rule
   over in [detection-engineering](https://github.com/manlikefelo/detection-engineering).
   *Shows:* I can execute an attack and detect it, and document it.
6. **[../README.md](../README.md#showcase)**: the *Showcase* and *Skills demonstrated*
   sections tie it together.

---

### If you only open one file
[`scripts/ad/03-inject-misconfigs.ps1`](../scripts/ad/03-inject-misconfigs.ps1).
It shows domain-security depth, safe automation, and clear teaching comments in one place.

### Things I was deliberate about
- **Zero secrets in git**: every password is prompted at runtime or read from a
  gitignored `.env`; certs and ISOs are generated/downloaded locally.
- **Reproducible**: numbered setup guides + idempotent scripts rebuild the lab from
  scratch.
- **Free & local**: VirtualBox, eval Windows images, Docker, Wazuh, Kali. No paid tooling.
