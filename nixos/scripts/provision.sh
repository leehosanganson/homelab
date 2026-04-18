#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <hostname> <target-ip>"
  echo ""
  echo "Provision a new NixOS node using nixos-anywhere."
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
EXTRA_FILES=$(mktemp -d)

cleanup() {
  rm -rf "$EXTRA_FILES"
}
trap cleanup EXIT

echo "--- 1. Updating Secrets ---"
nix flake update sops-secrets
git add .

echo "--- 2. Preparing extra-files for SSH host keys ---"
install -d -m 0755 "$EXTRA_FILES/etc"
install -d -m 0700 "$EXTRA_FILES/etc/ssh"
cp keys/"$HOSTNAME" "$EXTRA_FILES/etc/ssh/"
chmod 0600 "$EXTRA_FILES/etc/ssh/$HOSTNAME"

echo "--- 3. Provisioning $HOSTNAME at $TARGET_IP ---"
nix run github:nix-community/nixos-anywhere -- \
  --flake ".#$HOSTNAME" \
  --extra-files "$EXTRA_FILES" \
  "root@$TARGET_IP"

echo "--- PROVISIONING COMPLETE ---"
