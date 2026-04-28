#!/usr/bin/env bash
# Upload a NixOS installer ISO to Proxmox and distribute it across all nodes.
#
# Workflow:
#   1. Upload the local ISO file to the first node via scp
#   2. Spread the ISO from the first node to all remaining nodes (node-to-node scp)
#   3. Verify the ISO is registered on every node via `pvesm list local`
#   4. Print the terraform.tfvars snippet to reference the ISO
#
# Pre-requisites:
#   - SSH access as root to all Proxmox nodes
#   - /var/lib/vz/template/iso/ must exist on all nodes (standard Proxmox layout)
#   - The first node's known_hosts must include all other nodes (for node-to-node scp)
#
# Notes:
#   - Quote glob patterns (e.g. "nixos-minimal-*.iso") to prevent local shell expansion
#     if you want the script to expand them — or resolve the path before calling the script
#   - pvesm list may take a moment to reflect a newly copied file on some Proxmox versions
#
# Usage:
#   ./sync-iso.sh <local-iso-path> <node> [<node> ...]
#
# Example:
#   ./sync-iso.sh ./result/iso/nixos-minimal-26.05.20260302.cf59864-x86_64-linux.iso pve01 pve02 pve03

set -euo pipefail

usage() {
  echo "Usage: $0 <local-iso-path> <node> [<node> ...]"
  echo ""
  echo "  local-iso-path  Path to the ISO file on your local machine"
  echo "  node            One or more Proxmox node hostnames (e.g. pve01 pve02 pve03)"
  echo "                  The ISO is uploaded to the first node, then spread to the rest."
  echo ""
  echo "Example:"
  echo "  $0 ./result/iso/nixos-minimal-26.05.20260302.cf59864-x86_64-linux.iso pve01 pve02 pve03"
  exit 1
}

LOCAL_ISO="${1:-}"
[[ -z "$LOCAL_ISO" ]] && usage

shift
NODES=("$@")
[[ ${#NODES[@]} -eq 0 ]] && usage

# Resolve the local path (handles relative paths and single-glob expansion)
LOCAL_ISO="$(realpath "$LOCAL_ISO")"
[[ ! -f "$LOCAL_ISO" ]] && { echo "ERROR: File not found: $LOCAL_ISO"; exit 1; }

ISO_FILENAME="$(basename "$LOCAL_ISO")"
ISO_PATH="/var/lib/vz/template/iso/${ISO_FILENAME}"

UPLOAD_NODE="${NODES[0]}"
SPREAD_NODES=("${NODES[@]:1}")

echo "==> ISO file     : ${ISO_FILENAME}"
echo "==> Upload node  : ${UPLOAD_NODE}"
if [[ ${#SPREAD_NODES[@]} -gt 0 ]]; then
  echo "==> Spread nodes : ${SPREAD_NODES[*]}"
fi
echo ""

# Step 1 — Upload local ISO to the first node
echo "==> [${UPLOAD_NODE}] Uploading ISO from local machine ..."
scp "$LOCAL_ISO" "root@${UPLOAD_NODE}:${ISO_PATH}"

echo "==> [${UPLOAD_NODE}] Verifying ISO registration via pvesm ..."
ssh "root@${UPLOAD_NODE}" "pvesm list local | grep '${ISO_FILENAME}'" \
  || { echo "==> [${UPLOAD_NODE}] ERROR: ISO not visible in pvesm list local"; exit 1; }
echo "==> [${UPLOAD_NODE}] ISO uploaded and verified."
echo ""

# Step 2 — Spread from the first node to all remaining nodes
for TARGET_NODE in "${SPREAD_NODES[@]}"; do
  echo "==> [${TARGET_NODE}] Copying ISO from ${UPLOAD_NODE} ..."
  ssh "root@${UPLOAD_NODE}" scp "${ISO_PATH}" "root@${TARGET_NODE}:${ISO_PATH}"

  echo "==> [${TARGET_NODE}] Verifying ISO registration via pvesm ..."
  ssh "root@${TARGET_NODE}" "pvesm list local | grep '${ISO_FILENAME}'" \
    || { echo "==> [${TARGET_NODE}] ERROR: ISO not visible in pvesm list local"; exit 1; }

  echo "==> [${TARGET_NODE}] ISO successfully synced and verified."
  echo ""
done

echo "==> All nodes have the ISO. Add this to terraform.tfvars:"
echo ""
echo "    nixos_iso = \"local:iso/${ISO_FILENAME}\""
