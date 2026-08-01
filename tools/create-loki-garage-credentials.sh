#!/usr/bin/env bash
# Bootstrap S3 credentials for Loki against an in-cluster Garage deployment.
#
# This script creates the loki and loki-ruler buckets, creates an S3 access key,
# grants it full access to both buckets, and prints the resulting credentials so
# they can be added to the Azure Key Vault used by External Secrets.
#
# Usage:
#   ./tools/create-loki-garage-credentials.sh
#
# Override defaults via environment variables if needed.

set -euo pipefail

: "${GARAGE_NAMESPACE:=monitoring}"
: "${GARAGE_POD:=garage-0}"
: "${GARAGE_KEY_NAME:=loki-key}"
: "${GARAGE_BUCKET_CHUNKS:=loki}"
: "${GARAGE_BUCKET_RULER:=loki-ruler}"
: "${KEY_VAULT_NAME:=lhs-kubernetes-keyvault}"
: "${ACCESS_KEY_SECRET_NAME:=loki-garage-s3-access-key}"
: "${SECRET_KEY_SECRET_NAME:=loki-garage-s3-secret-key}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is required" >&2
  exit 1
fi

garage_exec() {
  kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- /garage "$@"
}

bucket_exists() {
  garage_exec bucket info "$1" >/dev/null 2>&1
}

echo "==> Creating buckets (if needed)"
if ! bucket_exists "${GARAGE_BUCKET_CHUNKS}"; then
  garage_exec bucket create "${GARAGE_BUCKET_CHUNKS}"
  echo "    created ${GARAGE_BUCKET_CHUNKS}"
else
  echo "    ${GARAGE_BUCKET_CHUNKS} already exists"
fi

if ! bucket_exists "${GARAGE_BUCKET_RULER}"; then
  garage_exec bucket create "${GARAGE_BUCKET_RULER}"
  echo "    created ${GARAGE_BUCKET_RULER}"
else
  echo "    ${GARAGE_BUCKET_RULER} already exists"
fi

echo "==> Creating or retrieving S3 key '${GARAGE_KEY_NAME}'"
if garage_exec key info "${GARAGE_KEY_NAME}" --show-secret >/dev/null 2>&1; then
  KEY_INFO=$(garage_exec key info "${GARAGE_KEY_NAME}" --show-secret)
  echo "    key already exists"
else
  KEY_INFO=$(garage_exec key create "${GARAGE_KEY_NAME}")
  echo "    created new key"
fi

ACCESS_KEY_ID=$(echo "${KEY_INFO}" | awk '/^Key ID:/{print $NF}')
SECRET_ACCESS_KEY=$(echo "${KEY_INFO}" | awk '/^Secret key:/{print $NF}')

if [[ -z "${ACCESS_KEY_ID}" || -z "${SECRET_ACCESS_KEY}" || "${SECRET_ACCESS_KEY}" == "(redacted)" ]]; then
  echo "ERROR: could not retrieve the secret key. Re-run with a key that exposes the secret." >&2
  exit 1
fi

echo "==> Granting key access to buckets"
garage_exec bucket allow --read --write --owner "${GARAGE_BUCKET_CHUNKS}" --key "${GARAGE_KEY_NAME}"
garage_exec bucket allow --read --write --owner "${GARAGE_BUCKET_RULER}" --key "${GARAGE_KEY_NAME}"

echo ""
echo "==> Loki Garage S3 credentials"
echo "    Access key ID: ${ACCESS_KEY_ID}"
echo "    Secret key:    ${SECRET_ACCESS_KEY}"
echo ""
echo "==> Add these to Azure Key Vault: ${KEY_VAULT_NAME}"
echo "    az keyvault secret set --vault-name ${KEY_VAULT_NAME} --name ${ACCESS_KEY_SECRET_NAME} --value ${ACCESS_KEY_ID}"
echo "    az keyvault secret set --vault-name ${KEY_VAULT_NAME} --name ${SECRET_KEY_SECRET_NAME} --value ${SECRET_ACCESS_KEY}"
echo ""
echo "    ExternalSecret will then create the 'loki-garage-s3-credentials' secret"
echo "    and Loki will start using Garage."

# Optionally upload the secrets directly if az is authenticated.
if command -v az >/dev/null 2>&1 && az account show >/dev/null 2>&1; then
  echo ""
  read -rp "Azure CLI is logged in. Upload these secrets to Key Vault now? [y/N] " answer
  if [[ "${answer}" == "y" || "${answer}" == "Y" ]]; then
    az keyvault secret set --vault-name "${KEY_VAULT_NAME}" --name "${ACCESS_KEY_SECRET_NAME}" --value "${ACCESS_KEY_ID}"
    az keyvault secret set --vault-name "${KEY_VAULT_NAME}" --name "${SECRET_KEY_SECRET_NAME}" --value "${SECRET_ACCESS_KEY}"
    echo "    secrets uploaded"
  fi
fi
