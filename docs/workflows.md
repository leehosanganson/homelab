# Workflows

<!-- Step-by-step procedures, SOPs, recurring processes, and deployment steps. See AGENTS.md for high-level conventions. -->

## Recurring Processes
- _No entries yet._

## Step Sequences
- _No entries yet._

## Procedural Conventions
- _No entries yet._

## FluxCD

### Testing a PR Branch Without Merging to Main <!-- added 2026-05-02 -->

Use this SOP to deploy and validate changes from a PR branch in-cluster via FluxCD, without merging into `main`.

**How it works:** The `flux-system` `GitRepository` is temporarily patched in-cluster to track the PR branch. Flux reconciles all Kustomizations against that branch within ~1 minute. After testing, the patch is reverted.

#### 1. Patch the GitRepository to track the PR branch

```bash
kubectl patch gitrepository flux-system -n flux-system \
  --type='merge' \
  -p '{"spec": {"ref": {"branch": "<PR-BRANCH-NAME>"}}}'
```

#### 2. Verify Flux picked up the branch

```bash
flux get sources git flux-system -n flux-system
# REVISION column should show <branch-name>@sha1:<commit-sha>
```

#### 3. Confirm all Kustomizations reconciled

```bash
flux get kustomizations -n flux-system
# All rows should show READY: True and the PR branch revision
```

#### 4. Test the change in-cluster (e.g., verify a new ConfigMap, check a UI, etc.)

#### 5. Revert to main when done

```bash
kubectl patch gitrepository flux-system -n flux-system \
  --type='merge' \
  -p '{"spec": {"ref": {"branch": "main"}}}'
```

**Notes:**
- This patches only the in-cluster resource — no git commits or file changes required.
- The patch is not persistent; a Flux self-reconciliation cycle (every 10m) will NOT revert it automatically since the patch mutates the live object. You must manually revert (step 5).
- All Kustomizations in the cluster will track the PR branch while the patch is active, not just the one under test. Keep this window short.
