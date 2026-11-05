# 05: Linux victim containers (UB01)

Goal: deploy deliberately vulnerable Linux services as **Docker containers** on UB01
(`10.10.10.30`) instead of full VMs: the RAM-saving decision from the architecture.

> **Reviewer note:** containerising the victims is what lets me rebuild a target with
> one command and keeps the whole Linux attack surface under 2 GB. See
> [../victims/docker-compose.yml](../victims/docker-compose.yml).

> These images are intentionally vulnerable. Only run them on the isolated
> host-only network (guide 01). Keep the NAT adapter **detached** during attacks.

---

## Prereqs (UB01, Ubuntu Server 22.04)
```bash
sudo apt update && sudo apt install -y docker.io docker-compose-plugin
sudo usermod -aG docker $USER && newgrp docker
```

## Bring the victims up
```bash
cd security-homelab/victims
docker compose up -d
docker compose ps
```

| Service | Reachable at | Use it for |
|---------|--------------|------------|
| OWASP Juice Shop | `http://10.10.10.30:3000` | Modern web attacks (injection, auth, XSS) |
| DVWA | `http://10.10.10.30:8080` | Classic SQLi / XSS / command injection |
| SSH victim | `ssh labuser@10.10.10.30 -p 2222` (`Password123`) | Brute-force / lateral-movement telemetry |

## Confirm the Wazuh agent forwards Linux logs
UB01 should already have the Wazuh agent (guide 04). Generate some noise and confirm
it lands in the SIEM:
```bash
# a few failed SSH logins to produce auth events
for i in 1 2 3; do ssh -p 2222 baduser@10.10.10.30 2>/dev/null; done
```
In the Wazuh dashboard, filter `agent.name: UB01` and look for SSH authentication
failure alerts (rule group `authentication_failed` / sshd).

## Teardown / rebuild
```bash
docker compose down        # stop victims
docker compose up -d        # fresh, clean instances
```

That's the full build. Run the checklist in
**[../docs/verification.md](../docs/verification.md)**.
