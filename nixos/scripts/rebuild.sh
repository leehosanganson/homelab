#!/usr/bin/env bash
# Deploy an updated NixOS configuration to an existing, running host.
#
# This script uses nixos-rebuild switch --target-host to build the NixOS
# closure locally and activate it on the remote machine over SSH.
#
# Usage:
#   ./rebuild.sh <hostname> <ip>
#
# Example:
#   ./rebuild.sh haproxy-1 192.168.1.251

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

echo "==> Updating sops-secrets flake input..."
nix flake update sops-secrets --flake "$FLAKE_ROOT"

echo "==> Deploying '$HOSTNAME' to $TARGET_IP..."
nixos-rebuild switch \
  --flake "$FLAKE_ROOT#$HOSTNAME" \
  --target-host "root@$TARGET_IP" \
  --build-host localhost

echo ""
echo "==> Rebuild complete!"
