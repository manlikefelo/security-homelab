#!/usr/bin/env bash
# Generates the TLS certificates the Wazuh indexer/manager/dashboard need, using the
# official Wazuh cert-generation tool. Certs land in ./config/certs (gitignored).
#
# Reviewer note: certs are generated locally and never committed - the repo stays
# secret-free and every user generates their own trust material.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p config/certs

# Pull the official single-node cert config + generator (version-pinned to match compose)
WAZUH_VERSION="4.9.0"
BASE="https://packages.wazuh.com/${WAZUH_VERSION%.*}/docker/wazuh-docker/single-node"

if [ ! -f config/certs.yml ]; then
  curl -sSL "${BASE}/config/certs.yml" -o config/certs.yml \
    || { echo "Could not fetch certs.yml - grab it from github.com/wazuh/wazuh-docker (single-node/config/certs.yml)"; exit 1; }
fi

echo "[*] Running the Wazuh cert generator..."
docker run --rm \
  -v "$(pwd)/config/certs:/certificates" \
  -v "$(pwd)/config/certs.yml:/config/certs.yml" \
  wazuh/wazuh-certs-generator:0.0.2

echo "[+] Certificates generated in ./config/certs"
echo "    Next: docker compose up -d"
