#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <hostname> <target-ip>"
  echo ""
  echo "Rebuild and deploy NixOS configuration to a remote node."
  echo ""
  echo "Arguments:"
  echo "  hostname    Flake hostname (e.g. haproxy-1)"
  echo "  target-ip   IP address of the target machine"
  echo ""
  echo "Example:"
  echo "  $0 haproxy-1 192.168.1.251"
  exit 1
}

if [ $# -ne 2 ]; then
  usage
fi

HOSTNAME=$1
TARGET_IP=$2

echo "--- 1. Updating Secrets ---"
nix flake update sops-secrets
git add .

echo "--- 2. Deploying $HOSTNAME to $TARGET_IP ---"
nixos-rebuild switch \
  --flake ".#$HOSTNAME" \
  --target-host "root@$TARGET_IP" \
  --use-remote-sudo

echo "--- DEPLOYMENT COMPLETE ---"
