#!/usr/bin/env bash
# Deploy an updated NixOS configuration to an existing, running host.
#
# This script:
#   1. Injects all pre-generated SSH key material from
#      ./keys/<hostname>/etc/ssh/ to /etc/ssh on the remote host
#      - private keys/files: 0600 root:root
#      - public keys (*.pub): 0644 root:root
#   2. Runs nixos-rebuild switch --target-host to build locally and activate
#      the system remotely over SSH as root
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
KEYS_HOST_DIR="$SCRIPT_DIR/keys/$HOSTNAME/etc/ssh"

if [[ ! -d "$KEYS_HOST_DIR" ]]; then
  echo "ERROR: Missing keys directory: $KEYS_HOST_DIR"
  echo "Expected layout: nixos/scripts/keys/<hostname>/etc/ssh/*"
  exit 1
fi

if ! find "$KEYS_HOST_DIR" -type f -print -quit | grep -q .; then
  echo "ERROR: No key files found under: $KEYS_HOST_DIR"
  exit 1
fi

echo "==> Injecting SSH key material from $KEYS_HOST_DIR..."
ssh "root@$TARGET_IP" 'rm -rf /tmp/nixos-ssh-keys && mkdir -p /tmp/nixos-ssh-keys'
scp -r "$KEYS_HOST_DIR/." "root@$TARGET_IP:/tmp/nixos-ssh-keys/"
ssh "root@$TARGET_IP" 'bash -s' <<'EOF'
set -euo pipefail

mkdir -p /etc/ssh
cd /tmp/nixos-ssh-keys

# Recreate directory tree under /etc/ssh with safe defaults.
while IFS= read -r -d '' d; do
  d="${d#./}"
  install -d -o root -g root -m 0755 "/etc/ssh/$d"
done < <(find . -mindepth 1 -type d -print0)

# Install all files with extension-based permissions.
while IFS= read -r -d '' f; do
  f="${f#./}"
  if [[ "$f" == *.pub ]]; then
    mode=0644
  else
    mode=0600
  fi

  install -D -o root -g root -m "$mode" "$f" "/etc/ssh/$f"
done < <(find . -type f -print0)

rm -rf /tmp/nixos-ssh-keys
test -r /etc/ssh/bootstrap-vm
EOF

echo "==> SSH key injection complete: /etc/ssh (all files from host key directory)"

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
