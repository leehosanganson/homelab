---
name: kubernetes-ops
description: >-
  Run Kubernetes, GitOps, NixOS, and homelab operational tasks safely. Load this skill when the user asks to inspect, change, deploy, or troubleshoot workloads in a cluster, or when editing NixOS/GitOps manifests. It emphasizes dry-run validation, declarative GitOps, and confirmation before destructive actions.
---

## Overview

Operate clusters and declarative infrastructure carefully. Prefer reading current state before changing it, validate every manifest change with a client-side dry run, and verify rollouts before moving on. This skill is for day-to-day operations, not cluster bootstrap or disaster recovery.

## Safety Rules

- Always run `kubectl apply --dry-run=client` (or `server`) before applying changes.
- Always check rollout status after applying: `kubectl rollout status ...`.
- Prefer declarative GitOps over imperative commands.
- Never run `kubectl delete` or other destructive commands without explicit user confirmation.
- Never make cluster-wide changes (e.g., changing a namespace, CRD, or network policy that affects many workloads) without confirming the blast radius with the user.
- If a command could evict pods, restart workloads, or change external endpoints, pause and explain the impact.

## Common Workflows

### Inspect a workload

```bash
kubectl get pods -n <namespace>
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --tail=100
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

Use `helm list -n <namespace>` and `helm get values <release> -n <namespace>` for Helm releases.

### Edit a manifest

1. Read the current manifest (`kubectl get ... -o yaml` or from the GitOps repo).
2. Make the smallest change that achieves the goal.
3. Validate: `kubectl apply --dry-run=client -f <file>`.
4. Apply: `kubectl apply -f <file>`.
5. Verify: `kubectl rollout status deployment/<name> -n <namespace>` (or equivalent).

### Roll back

Only after confirming with the user:

```bash
kubectl rollout undo deployment/<name> -n <namespace>
```

### Troubleshoot

- Check events and recent logs.
- Verify resource requests/limits and node capacity.
- Confirm DNS and networking (Services, Ingress, NetworkPolicies).
- Inspect `helm history` before rollback.

## NixOS/GitOps

For NixOS flakes or GitOps repositories (Kustomize, Helm charts, Argo CD, Flux):

1. Locate the relevant file (`flake.nix`, `kustomization.yaml`, `values.yaml`, chart templates, etc.).
2. Edit the declaration.
3. Validate locally if a tool exists (`nix flake check`, `helm template`, `kustomize build`, `kubeconform`).
4. Commit the change with a clear message explaining the operational reason.
5. Let the GitOps controller reconcile, or apply manually with `--dry-run=client` first.
6. Verify the cluster state matches intent.

Prefer storing changes in Git over ad-hoc `kubectl edit`. If you must `kubectl edit`, be prepared to backport the change to Git.

## Escalation

Ask the user before:

- Deleting any resource.
- Applying changes to multiple namespaces or cluster-scoped resources.
- Changing storage, ingress controllers, cert-manager, or network policies.
- Running `helm upgrade` with breaking values changes.
- Any action that could cause downtime.

When in doubt, describe the planned command and its impact, then wait for approval.