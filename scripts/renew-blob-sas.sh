#!/usr/bin/env bash
set -euo pipefail
# Disable tracing before handling credentials, even if the caller used `bash -x`.
case $- in *x*) set +x ;; esac

readonly DEFAULT_EXPIRY_DAYS=30
readonly ESO_TIMEOUT_SECONDS=180
readonly ESO_POLL_SECONDS=5

usage() {
  cat <<'USAGE'
Renew a container SAS and sync it through an Azure Key Vault ExternalSecret.

Usage:
  renew-blob-sas.sh --subscription NAME --storage-account NAME --container NAME \\
    --key-vault NAME --key-vault-secret NAME --namespace NAME \\
    --external-secret NAME --secret NAME --secret-key KEY [options] [--apply | --confirm]

Required rotation target:
  --subscription NAME          Azure subscription name or ID
  --storage-account NAME       Azure Storage account
  --container NAME             Blob container
  --key-vault NAME             Azure Key Vault
  --key-vault-secret NAME      Key Vault secret to update
  --namespace NAME             Kubernetes namespace
  --external-secret NAME       ExternalSecret that reads the Key Vault secret
  --secret NAME                Target Kubernetes Secret
  --secret-key KEY             Target Secret data key

Optional:
  --expiry-days 1..30           SAS lifetime in days (default: 30)
  --apply                      Apply without an interactive prompt
  --confirm                    Ask for interactive confirmation before applying
  -h, --help                   Show this help

Without --apply or --confirm, the script only prints a preview. It does not
fetch credentials or make Azure/Kubernetes changes. SAS tokens are signed with
the storage account key (not a user delegation key). The script updates the
Key Vault secret, requests an ExternalSecret refresh, and waits for matching
SHA-256 fingerprints in Key Vault and the target Secret. It does not restart
workloads or perform database checks.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

subscription=
storage_account=
container=
key_vault=
key_vault_secret=
namespace=
external_secret=
kubernetes_secret=
secret_key=
expiry_days=$DEFAULT_EXPIRY_DAYS
mode=preview

while (($#)); do
  case "$1" in
    --subscription|--storage-account|--container|--key-vault|--key-vault-secret|--namespace|--external-secret|--secret|--secret-key|--expiry-days)
      option=$1
      (($# >= 2)) || fail "$option requires a value"
      value=$2
      [[ -n $value && $value != --* ]] || fail "$option requires a non-empty value"
      case "$option" in
        --subscription) subscription=$value ;;
        --storage-account) storage_account=$value ;;
        --container) container=$value ;;
        --key-vault) key_vault=$value ;;
        --key-vault-secret) key_vault_secret=$value ;;
        --namespace) namespace=$value ;;
        --external-secret) external_secret=$value ;;
        --secret) kubernetes_secret=$value ;;
        --secret-key) secret_key=$value ;;
        --expiry-days) expiry_days=$value ;;
      esac
      shift 2
      ;;
    --apply)
      [[ $mode == preview ]] || fail 'Use only one of --apply and --confirm'
      mode=apply
      shift
      ;;
    --confirm)
      [[ $mode == preview ]] || fail 'Use only one of --apply and --confirm'
      mode=confirm
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1 (use --help)"
      ;;
  esac
done

[[ -n $subscription ]] || fail '--subscription is required'
[[ -n $storage_account ]] || fail '--storage-account is required'
[[ -n $container ]] || fail '--container is required'
[[ -n $key_vault ]] || fail '--key-vault is required'
[[ -n $key_vault_secret ]] || fail '--key-vault-secret is required'
[[ -n $namespace ]] || fail '--namespace is required'
[[ -n $external_secret ]] || fail '--external-secret is required'
[[ -n $kubernetes_secret ]] || fail '--secret is required'
[[ -n $secret_key ]] || fail '--secret-key is required'

[[ $expiry_days =~ ^[0-9]+$ ]] || fail '--expiry-days must be an integer from 1 to 30'
((expiry_days >= 1 && expiry_days <= 30)) || fail '--expiry-days must be from 1 to 30'
subscription_re='^[A-Za-z0-9][A-Za-z0-9._ -]*$'
[[ $subscription =~ $subscription_re ]] || fail 'Invalid Azure subscription name or ID'
[[ $storage_account =~ ^[a-z0-9]{3,24}$ ]] || fail 'Invalid Azure storage account name'
[[ $container =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ ]] || fail 'Invalid Azure container name'
[[ $key_vault =~ ^[A-Za-z][A-Za-z0-9-]{1,22}[A-Za-z0-9]$ ]] || fail 'Invalid Key Vault name'
[[ $key_vault_secret =~ ^[A-Za-z0-9-]+$ && ${#key_vault_secret} -le 127 ]] || fail 'Invalid Key Vault secret name'
[[ $namespace =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ && ${#namespace} -le 63 ]] || fail 'Invalid Kubernetes namespace'
kubernetes_name_re='^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$'
[[ $external_secret =~ $kubernetes_name_re && ${#external_secret} -le 253 ]] || fail 'Invalid ExternalSecret name'
[[ $kubernetes_secret =~ $kubernetes_name_re && ${#kubernetes_secret} -le 253 ]] || fail 'Invalid Kubernetes Secret name'
[[ $secret_key =~ ^[A-Za-z0-9._-]+$ && ${#secret_key} -le 253 ]] || fail 'Invalid Kubernetes Secret data key'

printf 'Azure Blob SAS renewal configuration\n'
printf '  Azure subscription: %s\n  Storage container:  %s/%s\n  Key Vault secret:   %s/%s\n' \
  "$subscription" "$storage_account" "$container" "$key_vault" "$key_vault_secret"
printf '  SAS permissions:    racwdl (account-key signed, HTTPS only)\n  Expiry:             %s days from now\n' "$expiry_days"
printf '  ESO target:         %s/%s key %s via ExternalSecret %s\n' \
  "$namespace" "$kubernetes_secret" "$secret_key" "$external_secret"

if [[ $mode == preview ]]; then
  printf '\nPreview only: no credentials were fetched and no changes were made.\n'
  printf 'Use --apply to proceed, or --confirm to review and confirm interactively.\n'
  exit 0
fi

if [[ $mode == confirm ]]; then
  [[ -t 0 ]] || fail '--confirm requires an interactive terminal; use --apply for an explicit non-interactive run'
  printf '\nType renew to update Key Vault and refresh the Kubernetes secret: '
  IFS= read -r answer
  [[ $answer == renew ]] || { printf 'Cancelled; no changes made.\n'; exit 0; }
fi

command -v az >/dev/null 2>&1 || fail 'Azure CLI (az) is required'
command -v kubectl >/dev/null 2>&1 || fail 'kubectl is required to refresh and verify the ExternalSecret'
command -v jq >/dev/null 2>&1 || fail 'jq is required to verify the ExternalSecret mapping and secret value'
command -v base64 >/dev/null 2>&1 || fail 'base64 is required to verify the Kubernetes Secret'
command -v sha256sum >/dev/null 2>&1 || fail 'sha256sum is required to compare secret fingerprints'

az account show --subscription "$subscription" >/dev/null 2>&1 || fail "Could not access Azure subscription '$subscription'; run az login first"
identity=$(az account show --subscription "$subscription" --query user.name -o tsv 2>/dev/null) || fail 'Could not read the Azure identity'
[[ -n $identity ]] || fail 'Azure CLI returned an empty identity'
actual_account=$(az storage account show --subscription "$subscription" --name "$storage_account" --query name -o tsv 2>/dev/null) || \
  fail "Could not confirm storage account '$storage_account' in subscription '$subscription'"
[[ $actual_account == "$storage_account" ]] || fail 'Azure returned an unexpected storage account'
cluster_context=$(kubectl config current-context 2>/dev/null) || fail 'Could not read the current Kubernetes context'
[[ -n $cluster_context ]] || fail 'kubectl has no current context'

external_secret_json=$(kubectl -n "$namespace" get externalsecret "$external_secret" -o json 2>/dev/null) || \
  fail "Could not find ExternalSecret $namespace/$external_secret in the current Kubernetes context"
jq -e --arg target "$kubernetes_secret" --arg key "$secret_key" --arg remote "$key_vault_secret" \
  '((.spec.target.name // .metadata.name) == $target) and any(.spec.data[]?; .secretKey == $key and .remoteRef.key == $remote)' \
  >/dev/null <<<"$external_secret_json" || \
  fail "ExternalSecret $namespace/$external_secret does not map Key Vault secret '$key_vault_secret' to $kubernetes_secret key '$secret_key'"
unset external_secret_json

printf '\nConfirmed Azure identity: %s\nSubscription: %s\nStorage account/container: %s/%s\nKubernetes context: %s\n' \
  "$identity" "$subscription" "$storage_account" "$container" "$cluster_context"

umask 077
secret_file=$(mktemp "${TMPDIR:-/tmp}/blob-sas.XXXXXX") || fail 'Could not create a private temporary file'
cleanup() {
  rm -f -- "$secret_file"
  unset account_key kv_value kv_fingerprint cluster_fingerprint
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
chmod 600 "$secret_file"

account_key=$(az storage account keys list --subscription "$subscription" --account-name "$storage_account" \
  --query 'keys[0].value' -o tsv 2>/dev/null) || fail 'Could not fetch the storage account key'
[[ -n $account_key && $account_key != None ]] || fail 'Azure returned an empty storage account key'
start=$(date -u -d '15 minutes ago' '+%Y-%m-%dT%H:%MZ') || fail 'Could not calculate the SAS start time'
expiry=$(date -u -d "+${expiry_days} days" '+%Y-%m-%dT%H:%MZ') || fail 'Could not calculate the SAS expiry time'
# AZURE_STORAGE_KEY avoids putting an account key in the Azure CLI process arguments.
if ! sas_generation_output=$(AZURE_STORAGE_KEY="$account_key" az storage container generate-sas \
  --subscription "$subscription" --account-name "$storage_account" --name "$container" \
  --permissions racwdl --start "$start" --expiry "$expiry" --https-only --auth-mode key -o tsv 2>/dev/null); then
  unset account_key
  fail 'SAS generation failed; Key Vault was not changed'
fi
unset account_key
printf '%s' "$sas_generation_output" | tr -d '\r\n' >"$secret_file"
unset sas_generation_output
[[ -s $secret_file ]] || fail 'Azure CLI generated an empty SAS token'

# --file avoids putting the SAS in az arguments or standard output.
az keyvault secret set --subscription "$subscription" --vault-name "$key_vault" --name "$key_vault_secret" \
  --file "$secret_file" --output none >/dev/null 2>&1 || fail 'Key Vault rejected the secret update'

kv_value=$(az keyvault secret show --subscription "$subscription" --vault-name "$key_vault" --name "$key_vault_secret" \
  --query value -o tsv 2>/dev/null) || fail 'Secret was set, but its Key Vault value could not be verified'
[[ -n $kv_value ]] || fail 'Key Vault returned an empty secret value after update'
kv_fingerprint=$(printf '%s' "$kv_value" | sha256sum | awk '{print $1}')
unset kv_value

kubectl -n "$namespace" annotate externalsecret "$external_secret" \
  "force-sync=$(date +%s)" --overwrite >/dev/null || \
  fail 'Key Vault was updated, but the ExternalSecret force-refresh request failed'

printf 'Key Vault updated. Waiting for ExternalSecret refresh and matching secret fingerprints...\n'
deadline=$((SECONDS + ESO_TIMEOUT_SECONDS))
while ((SECONDS < deadline)); do
  ready=$(kubectl -n "$namespace" get externalsecret "$external_secret" \
    -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  cluster_fingerprint=$(kubectl -n "$namespace" get secret "$kubernetes_secret" -o json 2>/dev/null | \
    jq -er --arg key "$secret_key" '.data[$key] // empty' 2>/dev/null | \
    base64 --decode 2>/dev/null | sha256sum | awk '{print $1}' || true)
  if [[ $ready == True && -n $cluster_fingerprint && $cluster_fingerprint == "$kv_fingerprint" ]]; then
    printf 'ESO refresh verified. Matching SHA-256 fingerprint: %s\n' "$kv_fingerprint"
    break
  fi
  sleep "$ESO_POLL_SECONDS"
done

[[ ${ready:-} == True && ${cluster_fingerprint:-} == "$kv_fingerprint" ]] || \
  fail "Timed out waiting for ESO to publish the updated secret in ${namespace}/${kubernetes_secret}; Key Vault is updated, but the Kubernetes secret was not verified"

printf '\nSAS rotation and ExternalSecret sync are complete. No workloads were restarted.\n'
