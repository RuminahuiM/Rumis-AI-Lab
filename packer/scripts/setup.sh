#!/usr/bin/env bash
# =============================================================================
# Packer provisioner – install Docker, NFS client, and open-vm-tools
# =============================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "── Installing Docker ──"
curl -fsSL https://get.docker.com | sh
usermod -aG docker rumis

echo "── Installing NFS client ──"
apt-get install -y nfs-common

echo "── Ensuring open-vm-tools is installed ──"
apt-get install -y open-vm-tools

echo "── Enabling cloud-init for first-boot customisation ──"
systemctl enable cloud-init

echo "── Cleanup ──"
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
cloud-init clean --logs
truncate -s 0 /etc/machine-id

echo "── Done ──"
