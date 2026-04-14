#!/bin/bash
VAULT_NAME="lhs-kubernetes-keyvault"
export GITHUB_TOKEN=$(az keyvault secret show --name fluxcd-github-token --vault-name $VAULT_NAME --query value -o tsv)
export GITHUB_USERNAME="leehosanganson"

flux bootstrap github \
    --token-auth \
    --owner=leehosanganson \
    --repository=homelab \
    --branch=main \
    --path=./fluxcd/clusters/production \
    --personal
