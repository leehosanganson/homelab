# Karakeep + Meilisearch Upgrade Migration Runbook

## Overview

This runbook covers upgrading **Karakeep** from `v0.32.0` → `v0.33.1` and **Meilisearch** from `v1.11.1` → `v1.50.0`.

The meilisearch upgrade is a prerequisite because Karakeep 0.33's new **semantic search** feature requires Meilisearch v1.13+. The version jump (1.11 → 1.50) spans ~39 minor versions, so a database migration is required.

## Prerequisites

- Both PRs merged: `chore/karakeep-meilisearch-upgrade-migration`
- FluxCD tracking the merge branch in-cluster (or already reconciled to main)
- Meilisearch data stored in PVC `meilisearch-pvc` mounted at `/meili_data`

## Migration Steps

### Step 1: Create a Dump of Current Meilisearch Data (v1.11.1)

Run a temporary migration pod using the **current** v1.11.1 image to create a dump into the shared PVC:

```bash
kubectl run meilisearch-migrate \
  -n karakeep \
  --image=getmeili/meilisearch:v1.11.1 \
  --restart=Never \
  --rm -i --stdin \
  --command=bash \
  --env="MEILI_MASTER_KEY=$(kubectl get secret karakeep-secrets -n karakeep -o jsonpath='{.data.MEILI_MASTER_KEY}' | base64 -d)" \
  -- \
  meilisearch --dump-dir=/meili_data/dumps --mode=export
```

Wait for the dump to complete, then verify:

```bash
kubectl exec -n karakeep -it $(kubectl get pods -n karakeep -l app=meilisearch -o jsonpath='{.items[0].metadata.name}') \
  -- ls /meili_data/dumps/
# Should show a file like: 20260802_120000_v1.11.1.dump
```

### Step 2: Stop Meilisearch Pod (v1.11.1)

Delete the current meilisearch pod so it picks up the new image from the deployment:

```bash
kubectl delete pod -n karakeep -l app=meilisearch --wait=false
```

### Step 3: Restore Database into New Meilisearch (v1.50.0)

After Flux reconciles and the new v1.50.0 pod starts, run a one-off restore:

```bash
kubectl run meilisearch-restore \
  -n karakeep \
  --image=getmeili/meilisearch:v1.50.0 \
  --restart=Never \
  --rm -i --stdin \
  --command=bash \
  --env="MEILI_MASTER_KEY=$(kubectl get secret karakeep-secrets -n karakeep -o jsonpath='{.data.MEILI_MASTER_KEY}' | base64 -d)" \
  -- \
  meilisearch --restore-db=/meili_data/dumps/<dump-filename>.dump
```

Wait for the restore to complete and verify:

```bash
kubectl logs -n karakeep job/meilisearch-restore
# Should show successful restoration messages
```

### Step 4: Verify Meilisearch is Running

Check that the meilisearch deployment is healthy:

```bash
kubectl rollout status -n karakeek deployment/meilisearch --timeout=120s
kubectl logs -n karakeep -l app=meilisearch --tail=20
# Should show startup messages without errors
```

Test connectivity from the Karakeep pod:

```bash
kubectl exec -n karakeep -it $(kubectl get pods -n karakeep -l app=karakeep-web -o jsonpath='{.items[0].metadata.name}') \
  -- curl -s http://meilisearch:7700/health
# Should return {"status":"available"}
```

### Step 5: Regenerate Embeddings in Karakeep

After verifying Meilisearch is running with v1.50.0:

1. Open the Karakeep web UI
2. Navigate to **Admin Panel** → **Background Jobs**
3. Find the new **"Embeddings"** card
4. Click **"Regenerate embeddings"** for all bookmarks

This will index all existing bookmarks with semantic search vectors. This may take a while depending on bookmark count and can incur API costs (though embeddings are usually cheap).

## Post-Upgrade Verification

- [ ] Meilisearch responds to `/health` endpoint
- [ ] Karakeep web UI loads without errors
- [ ] Search works in both keyword and semantic modes
- [ ] Existing bookmarks and tags are intact
- [ ] Crawler can save new bookmarks successfully

## Rollback Plan

If anything goes wrong:

1. Revert the PR branch back to main (or patch GitRepository to track main)
2. Restore from the last known good dump:
   ```bash
   # Use v1.11.1 image with --restore-db pointing to the same dump file
   ```
3. Karakeep will show errors until meilisearch is back on v1.11.1

## Notes

- **Breaking changes in Meilisearch v1.50**: `dynamicSearchRules` experimental feature has API changes (request/response format). This shouldn't affect Karakeep since it doesn't use DSRs.
- The dump file remains on the PVC after migration — you can safely delete old dumps once verified.
- Consider enabling embeddings config in Karakeep if using a custom AI provider (see Karakeep docs).
