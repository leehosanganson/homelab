#!/usr/bin/env bash
# Rotate the Entra ID client secret used by External Secrets Operator (azure-keyvault store)
# and update the azure-sp-secret it reads, then trigger a re-sync.
#
# Usage:
#   bash tools/regenerate-eso-client-secret.sh --app-id <id>
#
# Flags:
#   --app-id <id>   Entra ID app (service principal) object/app ID to rotate (required)
#   --kubeconfig    Path to kubeconfig (defaults to $KUBECONFIG or ~/.kube/config)
set -euo pipefail

NS="external-secrets"
SECRET="azure-sp-secret"
STORE="azure-keyvault"
TENANT_ID="64d56fc8-65a6-4591-9a23-5b6a47b2cf29"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-id)    APP_ID="$2"; shift 2 ;;
    --kubeconfig) export KUBECONFIG="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${APP_ID:-}" ]]; then
  echo "ERROR: --app-id is required (Entra ID app/SP to rotate)" >&2
  exit 1
fi

for cmd in az kubectl; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found" >&2; exit 1; }
done

echo "==> Rotating client secret for app $APP_ID (appending, keeping old valid)"
# --append keeps the existing secret valid until the new one is verified, avoiding an auth gap.
SP_OUTPUT="$(az ad app credential reset --id "$APP_ID" --append --years 1 -o json)"
NEW_SECRET="$(printf '%s' "$SP_OUTPUT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["password"])')"

echo "==> Updating k8s Secret $NS/$SECRET"
kubectl -n "$NS" create secret generic "$SECRET" \
  --from-literal=ClientID="$APP_ID" \
  --from-literal=ClientSecret="$NEW_SECRET" \
  --from-literal=TenantID="$TENANT_ID" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Restarting external-secrets to pick up new credential"
kubectl -n "$NS" rollout restart deploy/external-secrets
kubectl -n "$NS" rollout status deploy/external-secrets --timeout=120s

echo "==> Forcing re-sync of ExternalSecrets using $STORE"
kubectl get externalsecret -A -o name | while read -r es; do
  kubectl annotate "$es" force-sync=true --overwrite >/dev/null
done

echo "==> Verifying store status"
kubectl get clustersecretstore "$STORE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'

echo "Done. Old client secret can now be deleted from the Entra ID app if the new one is confirmed working."
