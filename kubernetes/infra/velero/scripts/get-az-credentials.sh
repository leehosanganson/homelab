#!/usr/bin/env bash
set -euo pipefail

# --- config ---
AZURE_RESOURCE_GROUP="homelab-kubernetes"
VELERO_SP_NAME="velero"
AZURE_KEYVAULT_NAME="lhs-kubernetes-keyvault"
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

# Check if everything is set
if [[ -z "$AZURE_SUBSCRIPTION_ID" || -z "$AZURE_TENANT_ID" || -z "$AZURE_CLIENT_ID" || -z "$AZURE_CLIENT_SECRET" ]]; then
  echo "[-] Failed to get credentials for Velero SP. Check 'az ad sp list --display-name \"$VELERO_SP_NAME\"' for more info."
  exit 1
fi

# Create / update secret and upload to az keyvault
az keyvault secret set --vault-name "$AZURE_KEYVAULT_NAME" \
  --name "velero-cloud-credentials" \
  --file <(cat <<EOF
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
AZURE_RESOURCE_GROUP=${AZURE_RESOURCE_GROUP}
EOF
)
