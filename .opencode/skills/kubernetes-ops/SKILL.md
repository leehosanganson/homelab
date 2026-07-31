---
name: kubernetes-ops
description: >-
  Work with Kubernetes, GitOps, NixOS, and homelab manifests. Load this skill when the user asks to inspect, change, validate, or troubleshoot infrastructure declarations in the repository. Covers local validation, declarative GitOps workflows, and safe cluster operations when kubectl is available.
---

## Overview

This repository is managed declaratively. Kubernetes manifests live under `kubernetes/`, NixOS configuration under `nixos/`, and the cluster reconciles desired state from Git.

## Capabilities

- Read and edit Kubernetes manifests (Kustomize base/overlays, Deployments, Services, PVCs, Ingresses, ExternalSecrets, etc.).
- Read and edit NixOS flakes and modules.
- Read and edit Helm values and chart templates.
- Validate manifests locally with available tools.
- Propose changes as PRs and let the GitOps controller reconcile after merge.
- Diagnose issues by reading manifests, docs, and runbooks.
- When running in an environment with cluster access (e.g., local opencode on a trusted machine), use `kubectl` for inspection and safe imperative commands.

## Local Validation

Before proposing changes, validate where possible:

- **Kustomize**: `kustomize build <overlay-path>` or `kubectl kustomize <overlay-path>`.
- **Dry-run**: `kubectl apply --dry-run=client -f <manifest>` (does not require a cluster).
- **Helm**: `helm template <release> <chart-path> -f <values-file>`.
- **NixOS**: `nix flake check` or `nix-instantiate --eval` on the relevant file.
- **Manifest schema**: `kubeconform` if available.

If a tool is not available, note it in your response and proceed with careful review.

## GitOps Workflow

1. Locate the relevant manifest or flake.
2. Make the smallest declarative change.
3. Validate locally if tools are available.
4. Commit and open a PR.
5. Let the GitOps controller reconcile after merge.
6. If the user wants live verification, ask them to run the appropriate cluster command or check the GitOps dashboard.

## Cluster Inspection (only when kubectl is available)

If the environment has a working kubeconfig and `kubectl`:

- Inspect workloads: `kubectl get pods`, `kubectl describe`, `kubectl logs`, `kubectl get events`.
- Verify rollouts: `kubectl rollout status`.
- Validate against server: `kubectl apply --dry-run=server -f <manifest>`.

When running in GitHub Actions, these commands are typically unavailable. Do not fabricate cluster state.

## Escalation

Ask the user before:

- Imperative cluster changes (`kubectl apply`, `kubectl delete`, `kubectl rollout`).
- Cluster-wide changes (namespaces, CRDs, network policies, storage classes).
- Operations that could cause downtime or restart workloads.
- Emergency rollbacks or recovery.

## Safety Rules

- Prefer declarative changes committed to Git.
- Never fabricate cluster state.
- When kubectl is unavailable, ask the user for live state or verification.
- Always validate locally before proposing changes if validation tools are available.
