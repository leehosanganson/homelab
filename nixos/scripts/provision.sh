#!/usr/bin/env bash
# Provision a new NixOS VM for the first time using nixos-anywhere + disko.
#
# This script:
#   1. Optionally injects pre-generated SSH host keys (for sops-nix Day-0 bootstrap)
#   2. Runs nixos-anywhere to partition the disk and install NixOS remotely
#
# Pre-requisites:
#   - The target VM must be booted into the NixOS installer ISO
#     (build with: nix build .#packages.x86_64-linux.installer)
#   - Root SSH access must be available on the target IP (password: nixos)
#
# Optional — stable host fingerprints & sops Day-0 secret decryption:
#   Pre-generate an SSH host key pair and place the files under
#   ./keys/<hostname>/etc/ssh/ before running this script.
#   nixos-anywhere will inject them via --extra-files.
#
# Usage:
#   ./provision.sh <hostname> <ip>
#
# Example:
#   ./provision.sh haproxy-1 192.168.1.251

set -euo pipefail

usage() {
  echo "Usage: $0 <hostname> <ip>"
  echo ""
  echo "  hostname  NixOS flake hostname (e.g. haproxy-1)"
  echo "  ip        Target VM IP address (e.g. 192.168.1.251)"
  exit 1
}

HOSTNAME="${1:-}"
TARGET_IP="${2:-}"

[[ -z "$HOSTNAME" ]] && usage
[[ -z "$TARGET_IP" ]] && usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_ROOT="$SCRIPT_DIR/.."
KEYS_DIR="$SCRIPT_DIR/keys"

echo "==> Provisioning '$HOSTNAME' at $TARGET_IP"

EXTRA_ARGS=()

# Inject pre-generated SSH host keys if a keys directory exists for this host.
# Expected layout: ./keys/<hostname>/etc/ssh/ssh_host_ed25519_key (and .pub)
if [[ -d "$KEYS_DIR/$HOSTNAME" ]]; then
  echo "==> Found SSH host keys at $KEYS_DIR/$HOSTNAME — injecting via --extra-files"
  EXTRA_ARGS+=(--extra-files "$KEYS_DIR/$HOSTNAME")
fi

nix run github:nix-community/nixos-anywhere -- \
  --flake "$FLAKE_ROOT#$HOSTNAME" \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} \
  "root@$TARGET_IP"

echo ""
echo "==> Provisioning complete!"
echo "    SSH into the new host: ssh root@$TARGET_IP"
