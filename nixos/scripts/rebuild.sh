#!/usr/bin/env bash
set -e # Exit immediately if any command fails

VM_ID=900
PVE_HOST="root@pve03.home.lab"
STORAGE="local-lvm"

echo "--- 1. Updating Secrets and Building Image ---"
nix flake update sops-secrets
git add .
nixos-rebuild build-image --flake .#haproxy-1 --image-variant proxmox

# Dynamically find the path of the built .vma.zst file
IMAGE_PATH=$(readlink -f ./result/*.vma.zst)
IMAGE_NAME=$(basename "$IMAGE_PATH")

echo "--- 2. Uploading $IMAGE_NAME to Proxmox ---"
scp "$IMAGE_PATH" "$PVE_HOST:/var/lib/vz/dump/"

echo "--- 3. Remote: Recreating VM $VM_ID ---"
# We pass the filename to the remote shell so it knows what to restore
ssh "$PVE_HOST" "bash -s" << EOF
  set -e
  echo "Stopping and Destroying existing VM..."
  qm stop $VM_ID || true
  qm destroy $VM_ID --purge || true

  echo "Restoring from /var/lib/vz/dump/$IMAGE_NAME..."
  qmrestore "/var/lib/vz/dump/$IMAGE_NAME" $VM_ID --storage $STORAGE --unique true
  
  echo "Starting VM..."
  qm start $VM_ID
  
  # Optional: Cleanup the uploaded image to save space on PVE
  rm "/var/lib/vz/dump/$IMAGE_NAME"
EOF

echo "--- DEPLOYMENT COMPLETE ---"
