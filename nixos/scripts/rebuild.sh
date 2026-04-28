#!/usr/bin/env bash
# Deploy an updated NixOS configuration to an existing, running host.
#
# This script uses nixos-rebuild switch --target-host to build the NixOS
# closure locally and activate it on the remote machine over SSH.
# It connects as the 'root' user on the remote machine.
#
# Usage:
#   ./rebuild.sh [--update-secrets] <hostname> <ip>
#
# Options:
#   --update-secrets  Run `nix flake update sops-secrets` before deploying.
#                     This mutates flake.lock; only use when you intentionally
#                     want to pull the latest secrets revision.
#
# Example:
#   ./rebuild.sh haproxy-1 192.168.1.251
#   ./rebuild.sh --update-secrets haproxy-1 192.168.1.251

set -euo pipefail

usage() {
  echo "Usage: $0 [--update-secrets] <hostname> <ip>"
  echo ""
  echo "  --update-secrets  Update the sops-secrets flake input before deploying"
  echo "  hostname          NixOS flake hostname (e.g. haproxy-1)"
  echo "  ip                Target VM IP address (e.g. 192.168.1.251)"
  echo ""
  echo "Connects as 'root' on the remote machine."
  exit 1
}

UPDATE_SECRETS=false

# Parse optional flag
if [[ "${1:-}" == "--update-secrets" ]]; then
  UPDATE_SECRETS=true
  shift
fi

HOSTNAME="${1:-}"
TARGET_IP="${2:-}"

[[ -z "$HOSTNAME" ]] && usage
[[ -z "$TARGET_IP" ]] && usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_ROOT="$SCRIPT_DIR/.."

if [[ "$UPDATE_SECRETS" == "true" ]]; then
  echo "==> Updating sops-secrets flake input (--update-secrets requested)..."
  echo "    WARNING: This will mutate flake.lock. Commit the result if intentional."
  nix flake update sops-secrets --flake "$FLAKE_ROOT"
fi

echo "==> Deploying '$HOSTNAME' to $TARGET_IP..."
nixos-rebuild switch \
  --flake "$FLAKE_ROOT#$HOSTNAME" \
  --target-host "root@$TARGET_IP"

echo ""
echo "==> Rebuild complete!"
