# LinkedIn post — Milestone 1: Domain Controller + Kali attacker

Milestone: built the Active Directory domain controller and the Kali attacker box for
a from-scratch red/blue home lab on a single 16GB laptop.

Copy everything under the marker. Add 2-3 screenshots (VirtualBox with the VMs, the
`Get-ADDomain` output, the Kali desktop) — screenshots lift LinkedIn reach a lot.

---POST---

I've started building a cybersecurity home lab from scratch, and I want to document it honestly — the wins and the parts that fought back.

The goal: one lab where I can play both sides. Attack an Active Directory environment like a red teamer, then turn around and catch those same attacks like a blue teamer. All of it on free tools, running on my 16GB laptop.

The constraint made it interesting. A full AD + SIEM lab doesn't fit in 16GB if everything runs at once, so I designed it to run in phases — the attacker VMs and the monitoring stack never need to be on at the same time. Every phase stays under ~12GB.

This week I got the two hardest pieces standing:

🖥️ The Domain Controller (Windows Server 2022)
I stood up a domain — "lab.local" — with Active Directory and DNS. Then I populated it like a real small company: 10 users across IT, Finance, HR, Sales and Engineering, sorted into groups and org units. Automated the whole thing with PowerShell so I can rebuild it anytime.

Then came the fun part — I deliberately broke it. I planted four classic misconfigurations that real Active Directory environments get wrong all the time:
• A service account that's crackable via Kerberoasting
• A user account exposed to AS-REP roasting
• A helpdesk account quietly given domain-replication rights (the setup for a DCSync attack)
• That same account nested into Domain Admins and forgotten about

Each one is a real attack path — and each one is something a defender should be able to detect. That symmetry is the whole point.

😈 The Kali attacker
Installed Kali Linux on its own isolated VM, ready to actually run those attacks against the domain.

And I'll be real — it was not smooth. The Windows installer hung on a black screen until I switched the VM's firmware from EFI to BIOS. The domain promotion failed the first time because a pending hostname change needed a reboot first. The Kali installer froze at the disk partitioner — twice — until I figured out it was the virtual disk controller and swapped it to IDE.

I'm actually glad those happened. Diagnosing a stuck installer, reading the error, forming a theory, testing it — that's the actual job. A lab that installs perfectly teaches you nothing.

Everything is documented in a public repo: architecture diagram, step-by-step build guides, the automation scripts, and a troubleshooting log of every issue and its fix. Building it so someone else could reproduce it from zero.

Next up: bring Kali online against the domain and run the first real attack — Kerberoasting — then stand up the SIEM and catch it.

More to come. If you're learning AD security or building your own lab, I'm happy to share what worked.

#CyberSecurity #ActiveDirectory #RedTeam #BlueTeam #HomeLab #InfoSec #Kali #LearningInPublic
