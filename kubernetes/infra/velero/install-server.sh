#!/usr/bin/env bash
set -euo pipefail

# --- config ---
BLOB_CONTAINER="velero"
AZURE_RESOURCE_GROUP="homelab-kubernetes"
AZURE_STORAGE_ACCOUNT_ID="lhshomelabbackup"
VELERO_SP_NAME="velero"
# -------------------------------

echo "[*] Getting default subscription and tenant..."
AZURE_SUBSCRIPTION_ID=$(az account list --query '[?isDefault].id' -o tsv)
AZURE_TENANT_ID=$(az account list --query '[?isDefault].tenantId' -o tsv)

echo "[*] Creating (or reusing) service principal '$VELERO_SP_NAME' with Contributor on RG '$AZURE_RESOURCE_GROUP'..."
# Try to create SP; if it already exists, capture/refresh password
AZURE_CLIENT_SECRET=$(az ad sp create-for-rbac \
  --name "$VELERO_SP_NAME" \
  --role "Contributor" \
  --scopes "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}" \
  --query 'password' -o tsv)

AZURE_CLIENT_ID=$(az ad sp list --display-name "$VELERO_SP_NAME" --query '[0].appId' -o tsv)

export AZURE_SUBSCRIPTION_ID
export AZURE_TENANT_ID
export AZURE_CLIENT_ID
export AZURE_CLIENT_SECRET
export AZURE_RESOURCE_GROUP

echo "[*] Installing Velero using environment credentials..."
velero install \
  --provider azure \
  --plugins velero/velero-plugin-for-microsoft-azure:v1.5.0 \
  --bucket $BLOB_CONTAINER \
  --secret-file /dev/stdin \
  --backup-location-config resourceGroup=$AZURE_RESOURCE_GROUP,storageAccount=$AZURE_STORAGE_ACCOUNT_ID,subscriptionId=$AZURE_SUBSCRIPTION_ID <<EOF
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
AZURE_RESOURCE_GROUP=${AZURE_RESOURCE_GROUP}
EOF

echo "[*] Velero install triggered. Check 'velero backup-location get' and 'kubectl get pods -n velero' for status."

