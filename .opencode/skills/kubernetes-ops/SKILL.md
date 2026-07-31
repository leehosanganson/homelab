---
name: kubernetes-ops
description: >-
  Work with Kubernetes, GitOps, NixOS, and homelab manifests in a CI/GitHub Actions environment without cluster access. Use this skill when the user asks to inspect, change, validate, or troubleshoot manifests in the repository. Emphasizes declarative GitOps, local validation, and escalation to humans for live cluster operations.
---

## Overview

You are running in a GitHub Actions runner without access to the homelab cluster. You cannot run `kubectl`, `helm` against the cluster, or any command that requires a live Kubernetes API. All cluster changes must be made declaratively in the repository and reconciled by the GitOps controller (e.g., Flux, Argo CD).

## What you CAN do

- Read and edit Kubernetes manifests in the repo.
- Read and edit NixOS flakes and modules in the repo.
- Read and edit Helm `values.yaml` and chart templates.
- Validate manifests locally using available tools.
- Open PRs and let the GitOps controller reconcile after merge.
- Diagnose issues by reading manifests, docs, and runbooks in the repo.

## What you CANNOT do

- Run `kubectl` commands (`get`, `apply`, `logs`, `describe`, `exec`, etc.).
- Access the cluster API, nodes, or pods directly.
- Run `helm install`/`upgrade`/`rollback` against the cluster.
- Perform imperative cluster changes.
- Restart, delete, or scale workloads directly.

## Local Validation

Before proposing changes, validate where possible:

- **Kustomize**: `kustomize build <overlay-path>` if `kustomize` is available.
- **Helm**: `helm template <release> <chart-path> -f <values-file>`.
- **NixOS**: `nix flake check` or `nix-instantiate --eval` on the relevant file.
- **YAML**: Check for syntax errors; use `kubeconform` if available in the runner.

If a validation tool is not available, note that in your response and proceed with careful review.

## Manifest Editing Workflow

1. Read the current manifest or flake.
2. Make the smallest declarative change that achieves the goal.
3. Validate locally if a tool is available.
4. Commit the change and open a PR.
5. Let the GitOps controller reconcile after merge.
6. Ask the user to verify the live cluster state if needed.

## Troubleshooting Without Cluster Access

When diagnosing issues:

- Read the relevant manifests, overlays, and secrets in the repo.
- Check `docs/runbooks/` for operational procedures.
- Check `README.md` and other docs for architecture and conventions.
- Look for common misconfigurations: wrong image tags, missing env vars, incorrect PVC paths, mismatched selectors, invalid ConfigMap references.
- Ask the user for live cluster state (pod status, logs, events) only when necessary.

## Escalation to Humans

Escalate to the user when any of these are needed:

- Live cluster state (`kubectl get`, `logs`, `describe`, `events`).
- Imperative fixes (`kubectl apply`, `kubectl rollout`, `kubectl delete`).
- Operations that may cause downtime or affect multiple workloads.
- Cluster-wide changes (namespaces, CRDs, network policies, storage classes).
- Emergency rollbacks or recovery.

## Safety Rules

- Never pretend to have run a cluster command.
- Never write `kubectl` commands in your response as if they were executed.
- Prefer declarative changes committed to Git.
- When unsure, ask the user to run the cluster command and report back.
