# Reviewer path — a 3-minute guided tour

Hi — thanks for taking a look. If you have three minutes, here's the fastest route
through this repo and what each stop proves about how I work.

---

### Minute 1 — the design (does this person think about constraints?)
1. **[architecture.md](architecture.md)** — read the mermaid diagram and the
   **phase-budget table**. The whole lab is engineered to run a full AD + SIEM
   detection environment on a **16 GB laptop** by never running the red VMs and the
   SIEM at once.
   → *Proves:* I design around real hardware constraints and can justify the trade-offs.
2. **[low-ram-operating-guide.md](low-ram-operating-guide.md)** — skim the three phase
   tables; each sums to ≤12 GB.
   → *Proves:* operational thinking, not just a wiring diagram.

### Minute 2 — the security depth (do they understand AD attack & defense?)
3. **[../scripts/ad/03-inject-misconfigs.ps1](../scripts/ad/03-inject-misconfigs.ps1)**
   — this is the file to read. Each intentional misconfiguration (Kerberoastable
   service account, AS-REP roastable user, DCSync-over-permission, Domain Admins
   nesting) has a **WHY** comment covering the attack (with MITRE ATT&CK IDs) **and**
   the defender's detection angle.
   → *Proves:* I understand offense and defense of the *same* finding, and I can
   automate it idempotently and secret-free.

### Minute 3 — the proof it works (is this real or aspirational?)
4. **[verification.md](verification.md)** — the checklist ending in a live
   Kerberoast → Wazuh alert. The screenshot placeholders are the evidence.
   → *Proves:* the attack → log → detect pipeline actually closes.
5. **[../projects/01-kerberoasting/RUN-LOG.md](../projects/01-kerberoasting/RUN-LOG.md)**
   — the one to open if you want *proof, not prose*: the actual command output and
   dashboard screenshots of the attack running and the matching Wazuh alert firing.
   The [projects index](../projects/) lists the same red→blue treatment for AS-REP
   roasting, DCSync and BloodHound, each with its own custom detection rule.
   → *Proves:* I can execute an attack and detect it — and document it honestly.
6. **[../README.md](../README.md#showcase)** — the *Showcase* and *Skills demonstrated*
   sections tie it together.

---

### If you only open one file
[`scripts/ad/03-inject-misconfigs.ps1`](../scripts/ad/03-inject-misconfigs.ps1) —
it shows domain-security depth, safe automation, and clear teaching comments in one place.

### Things I was deliberate about
- **Zero secrets in git** — every password is prompted at runtime or read from a
  gitignored `.env`; certs and ISOs are generated/downloaded locally.
- **Reproducible** — numbered setup guides + idempotent scripts rebuild the lab from
  scratch.
- **Free & local** — VirtualBox, eval Windows images, Docker, Wazuh, Kali. No paid tooling.
