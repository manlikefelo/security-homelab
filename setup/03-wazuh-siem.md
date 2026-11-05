# 03: Wazuh single-node SIEM (WAZUH01)

Goal: bring up a single-node Wazuh stack (indexer + manager + dashboard) via
docker-compose on WAZUH01 (`10.10.10.50`), ready to receive agent logs.

> **Note:** the [`docker-compose.yml`](../wazuh/docker-compose.yml) pins
> image versions and reads **all** credentials from a gitignored `.env`. Certs are
> generated locally by [`generate-certs.sh`](../wazuh/generate-certs.sh). The repo
> ships zero secrets.

---

## Prereqs (on WAZUH01, Ubuntu Server 22.04)
```bash
# Docker + compose plugin
sudo apt update && sudo apt install -y docker.io docker-compose-plugin curl
sudo usermod -aG docker $USER && newgrp docker
# OpenSearch kernel requirement (persist it):
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-wazuh.conf
sudo sysctl -w vm.max_map_count=262144
```

## Step 1: Configure secrets + certs
```bash
cd security-homelab/wazuh
cp .env.example .env
nano .env                     # set strong INDEXER/API/DASHBOARD passwords
chmod +x generate-certs.sh
./generate-certs.sh           # creates ./config/certs (gitignored)
```

## Step 2: Bring the stack up
```bash
docker compose up -d
docker compose ps             # all three services should be "running"/"healthy"
```
First start takes a few minutes (indexer initialises). Give it ~2–3 min on a 6 GB VM.

## Step 3: Log in to the dashboard
Open **`https://10.10.10.50:5601`** from the host or Kali browser.
- Username: `admin`
- Password: the `INDEXER_PASSWORD` you set in `.env`
- Accept the self-signed cert warning (expected: certs are lab-generated).

## Step 4: Note the enrollment endpoint
Agents enroll against the manager on **`10.10.10.50:1515`** and send events on
**`1514`**. Guide 04 installs the agents on every host and points them here.

## RAM note
This stack is the reason the lab is phased, see
[../docs/low-ram-operating-guide.md](../docs/low-ram-operating-guide.md). The compose
file caps the OpenSearch heap at 1 GB (`-Xms1g -Xmx1g`) to fit a 6 GB VM. On the
minimum-viable 4 GB profile it still runs but indexing is slower.

## Teardown
```bash
docker compose down            # stop (keeps volumes/data)
docker compose down -v         # stop AND wipe indexed data
```

Next: **[04-sysmon-and-agents.md](04-sysmon-and-agents.md)**
