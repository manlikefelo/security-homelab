# Twitter/X thread — Milestone 1: Domain Controller + Kali attacker

Post tweet 1, then reply with each following tweet to form a thread. Each is under 280
chars. Drop a screenshot on tweets 3, 5 and 8 if you can.

---POST---

🧵 1/
I'm building a full red team + blue team cybersecurity home lab from scratch on a single 16GB laptop. Free tools only.

Going to document the whole thing — including the parts that broke. Here's where I'm at 👇

2/
The idea: one lab where I attack an Active Directory network like a hacker, then detect those same attacks like a defender.

Trick is fitting it in 16GB. So I run it in phases — attacker VMs and the monitoring stack are never on at once. Every phase stays under ~12GB.

3/
First big piece: the Domain Controller.

Windows Server 2022, domain "lab.local", with Active Directory + DNS. I filled it with a fake company — 10 users across IT, Finance, HR, Sales, Engineering. All automated with PowerShell so I can rebuild it in minutes.

4/
Then I deliberately broke it 😈

Planted 4 classic AD misconfigs that real networks get wrong:
• Kerberoastable service account
• AS-REP roastable user
• Helpdesk account with DCSync rights
• That account hiding in Domain Admins

Every one is a real attack path.

5/
Second piece: Kali Linux on its own isolated VM. The attacker box. Ready to actually run those attacks against the domain.

6/
Real talk — none of this installed cleanly 😅

• Windows hung on a black screen → fixed by switching EFI to BIOS
• Domain promotion failed → pending rename needed a reboot first
• Kali froze at partitioning TWICE → it was the disk controller, swapped to IDE

7/
Honestly? Glad it broke.

Reading the error, forming a theory, testing the fix — that IS the job. A lab that installs perfectly teaches you nothing. Every hang taught me something.

8/
It's all in a public repo: architecture diagram, build guides, automation scripts, and a troubleshooting log of every issue + fix. Built so anyone could reproduce it from zero.

9/
Next up: Kali goes live against the domain for the first real attack — Kerberoasting — then I stand up the SIEM and try to catch it.

Following along? I'll keep sharing what works. 🔒

#CyberSecurity #ActiveDirectory #RedTeam #BlueTeam #Kali #InfoSec
