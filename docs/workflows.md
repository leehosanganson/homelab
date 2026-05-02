# Workflows

<!-- Step-by-step procedures, SOPs, recurring processes, and deployment steps. See AGENTS.md for high-level conventions. -->

## 🧪 Testing & Validation

Procedures for safely testing changes in-cluster before merging to `main`.

### Test a PR Branch in-Cluster via FluxCD

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

## 🔧 Operations & Maintenance

Step-by-step procedures for day-to-day operations, troubleshooting, and maintenance tasks.

- _No entries yet._

## 🔄 Recurring Processes

Scheduled or periodic tasks that should be repeated over time.

- _No entries yet._
