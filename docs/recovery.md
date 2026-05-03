# Cluster Recovery Playbook

This document is the step-by-step playbook for recovering the Kubernetes cluster from scratch. It covers bootstrapping Flux, restoring stateful workloads via Velero, recovering CNPG databases from barman backups, and allowing Flux to reconcile the rest.

## Overview

Recovery must follow a strict order because later phases depend on resources created in earlier ones.

```
Phase 1: Bootstrap Flux
     ↓
Phase 2: Reconcile Infrastructure (External Secrets → Storage → Velero → CNPG → Harbor)
     ↓
Phase 3: Velero Restore (apps + harbor namespaces)
     ↓
Phase 4: CNPG Database Recovery (automatic via recovery bootstrap)
     ↓
Phase 5: Reconcile Monitoring
     ↓
Phase 6: Reconcile Applications (stateless services)
```

---

## Prerequisites

Ensure the following tools are available and configured before starting:

- `kubectl` configured against the new cluster
- Azure CLI (`az`) authenticated with access to `lhs-kubernetes-keyvault`
- `flux` CLI installed
- `velero` CLI installed
- The Azure Service Principal credentials for External Secrets Operator (ClientID, ClientSecret)
  - These are stored in Azure Key Vault; retrieve them with:
    ```bash
    az keyvault secret show --vault-name lhs-kubernetes-keyvault --name <sp-client-id-secret>
    az keyvault secret show --vault-name lhs-kubernetes-keyvault --name <sp-client-secret-secret>
    ```

---

## Phase 1: Bootstrap Flux

Flux is the foundation — it manages all other resources. Bootstrap it first using the script at `fluxcd/bootstrap.sh`.

```bash
# Run from the repo root; the script reads the GitHub token from Azure Key Vault
./fluxcd/bootstrap.sh
```

This creates the `flux-system` namespace and installs Flux components. Flux will then attempt to reconcile `infra-production`, `monitoring-production`, and `apps-production` kustomizations — most will fail initially because External Secrets Operator (ESO) has not yet synced any secrets. That is expected.

**Verify Flux is running:**

```bash
kubectl get pods -n flux-system
flux get kustomizations
```

---

## Phase 2: Reconcile Infrastructure

### Step 2.1 — Seed the External Secrets Service Principal

ESO authenticates to Azure Key Vault via a Service Principal. This secret cannot be managed by ESO itself (that would be circular), so it must be seeded manually before ESO can pull any other secrets.

```bash
kubectl create namespace external-secrets

kubectl create secret generic azure-sp-secret \
  --namespace=external-secrets \
  --from-literal=ClientID=<sp-client-id> \
  --from-literal=ClientSecret=<sp-client-secret>
```

> The secret name and required keys are referenced in
> `kubernetes/infra/external-secrets/overlays/default/azure-kv-secret.yaml.example`.

### Step 2.2 — Reconcile Infrastructure

Trigger a reconcile and wait for all infra components to become ready:

```bash
flux reconcile kustomization infra-production --with-source
flux get kustomizations --watch
```

Flux installs components in order (as defined in `kubernetes/infra/overlays/production/kustomization.yaml`):

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| Cert Manager | `cert-manager` | TLS certificate issuance |
| External Secrets Operator | `external-secrets` | Pulls secrets from Azure Key Vault |
| Traefik | `traefik` | Ingress controller |
| Synology CSI | `synology-csi` | Storage class provisioner |
| CloudNativePG | `cnpg-system` | PostgreSQL cluster operator |
| Velero | `velero` | Backup / restore agent |
| Rancher | `cattle-system` | Cluster management UI |
| Harbor | `harbor` | Container registry (stateful; PVCs restored via Velero in Phase 3) |
| Renovate | `renovate` | Dependency update automation |

### Step 2.3 — Verify Velero Is Ready

Velero must be available before restoring backups in Phase 3.

```bash
kubectl get pods -n velero
velero get backup-locations
```

The `default` backup storage location must show `Available`. If it shows `Unavailable`, check that ESO has synced the `cloud-credentials` secret in the `velero` namespace:

```bash
kubectl get externalsecret -n velero
kubectl get secret cloud-credentials -n velero
```

---

## Phase 3: Velero Restore

### What Velero Backs Up

The Velero schedule (`kubernetes/infra/velero/overlays/default/backup-schedule.yaml`) runs daily at 07:00 UTC. It captures **Kubernetes object manifests** for `deployments`, `pods`, `persistentvolumes`, `persistentvolumeclaims`, and `namespaces`. Volume data is **not** included in the file-system backup (`defaultVolumesToFsBackup: false`).

Because all storage classes used (`synology-retain`, `nfs-csi-retain`) are **retain** classes backed by a Synology NAS, the actual data on the NAS persists across cluster rebuilds. Velero's role is to restore the PVC/PV binding and Deployment objects so that applications re-attach to the same NAS volumes after the cluster is rebuilt.

### Namespaces Covered

| Namespace | Contents / Notes |
|-----------|-----------------|
| `actual-budget` | Deployment, PVC |
| `grimmory` | Deployment, MariaDB PVC, data PVCs, NFS book-library PV/PVC |
| `harbor` | All Harbor PVCs: registry (50Gi), database (5Gi), jobservice (1Gi), redis (1Gi), trivy (5Gi) |
| `home-assistant` | Deployment, PVC |
| `immich` | Deployment, NFS photo library PV/PVC |
| `karakeep` | Deployment, PVCs (app + meilisearch) |
| `llm` | Open WebUI deployment, PVC |
| `media` | All *arr deployments + Jellyfin PVCs, NFS media/downloads PV/PVC |
| `minecraft` | Deployment, 50Gi game data PVC (`synology-retain`) |
| `n8n` | Deployment, PVC (database backed up separately via CNPG) |
| `navidrome` | Deployment, config PVC (1Gi), NFS music PV/PVC |
| `paperless` | Deployment, PVCs (database backed up separately via CNPG) |
| `syncthing` | Deployment, config PVC (1Gi), NFS sync-data PV/PVC |
| `zotero` | Deployment, PVC (10Gi) |

> **Note:** The `monitoring` namespace is intentionally excluded. Prometheus metrics are re-scraped after recovery, and Loki/Grafana/Uptime Kuma configurations are trivial to restore or rebuild.

### Step 3.1 — List Available Backups

```bash
velero get backups
```

Backups are retained for 10 days (240h TTL). Use the most recent backup name in the steps below.

### Step 3.2 — Restore All Covered Namespaces

```bash
velero restore create --from-backup <backup-name>
```

To restore a single namespace only:

```bash
velero restore create \
  --from-backup <backup-name> \
  --include-namespaces actual-budget
```

### Step 3.3 — Monitor Restore Progress

```bash
velero restore get
velero restore describe <restore-name> --details
```

Wait until the restore shows `Completed`. Then verify PVCs are `Bound`:

```bash
kubectl get pvc -A | grep -v Bound
```

All PVCs must be `Bound` before proceeding. If a PVC is `Pending`, see [Velero PVC troubleshooting](#velero-restore-fails-for-pvcs).

---

## Phase 4: CNPG Database Recovery

CNPG clusters continuously archive WAL to Azure Blob Storage via the barman-cloud plugin. All cluster manifests use `bootstrap.recovery` (in the overlay) so Flux automatically recovers each database from its latest barman backup when the cluster is first created on the new cluster.

> **How this works:** The base `db.yaml` files contain `bootstrap.initdb` for fresh cluster provisioning. Each app's overlay overrides only the `bootstrap` section with `recovery.bootstrap.source: clusterBackup`. During recovery, Flux applies the overlay and CNPG recovers from barman. On a fresh cluster (no backup), the base `initdb` is used instead.

### Cluster Inventory

| Cluster | Namespace | Barman Object Store | Azure Blob Path |
|---------|-----------|--------------------|-----------------|
| `immich-db` | `immich` | `immich-backup-storage` | `lhshomelabbackup/immich` |
| `n8n-db` | `n8n` | `n8n-backup-storage` | `lhshomelabbackup/n8n` |
| `paperless-db` | `paperless` | `paperless-backup-storage` | `lhshomelabbackup/paperless` |
| `commafeed-db` | `commafeed` | `commafeed-backup-storage` | `lhshomelabbackup/commafeed` |
| `litellm-db` | `litellm` | `litellm-backup-storage` | `lhshomelabbackup/litellm` |
| `coder-db` | `coder` | `coder-backup-storage` | `lhshomelabbackup/coder` |
| `life-in-the-uk-quiz-db` | `life-in-the-uk-quiz` | `life-in-the-uk-quiz-backup-storage` | `lhshomelabbackup/life-in-the-uk-quiz` |

### Step 4.1 — Pre-flight: Verify Barman Backups Exist

Before CNPG creates a cluster, verify that barman backups are available for each database. Run this check for every namespace that needs recovery:

```bash
# Example for immich:
kubectl exec -it $(kubectl get pod -l cnpg.io/cluster=immich-db -n immich -o name 2>/dev/null | head -1) \
  -n immich -- barman-cloud-backup-list --format json lhshomelabbackup/immich immich-db-backup 2>/dev/null

# If no pods exist yet (fresh cluster), check Azure Blob directly:
az storage blob list --container-name <barman-container> --output table
```

If a barman backup is missing for a namespace, that database must be bootstrapped fresh using `initdb` (see Step 4.3).

### Step 4.2 — Verify ObjectStore and Secrets Exist

Before CNPG creates a cluster, the `ObjectStore` resource and its backing secret (synced by ESO) must exist in the namespace. Flux deploys these as part of the app kustomization ahead of the Cluster resource.

```bash
# Check for each namespace that needs recovery, e.g. immich:
kubectl get objectstore -n immich
kubectl get secret -n immich | grep backup
```

If the `ObjectStore` secret is missing, force ESO to sync:

```bash
kubectl annotate externalsecret -n <namespace> <name> \
  force-sync=$(date +%s) --overwrite
```

### Step 4.3 — Handle Fresh Clusters (No Prior Barman Backups)

If a cluster has no prior barman backup, the overlay recovery mode will fail because there is nothing to recover from. In this case, temporarily switch to `initdb` in the overlay:

1. **Edit the overlay `db.yaml`** for the affected app and replace:
   ```yaml
   bootstrap:
     recovery:
       source: clusterBackup
   ```
   with:
   ```yaml
   bootstrap:
     initdb:
       database: <app-db-name>
       owner: <app-username>
       secret:
         name: <existing-secret-ref>
   ```

2. **Trigger Flux to reconcile:**
   ```bash
   flux reconcile kustomization apps-production --with-source
   ```

3. **Wait for the cluster to initialise** (check `kubectl get cluster -n <namespace>`).

4. **Once WAL archiving produces a full base backup**, revert the overlay back to `recovery` mode so future restores work automatically.

> **Per-database notes:**
> - **immich**: After fresh initdb, run manually: `CREATE EXTENSION vchord CASCADE; CREATE EXTENSION earthdistance CASCADE;`
> - **All others**: Standard initdb is sufficient.

### Step 4.4 — Watch Recovery Progress

Once Flux reconciles the app kustomization, CNPG creates the cluster and begins recovery automatically:

```bash
# Watch all CNPG clusters
kubectl get cluster -A -w

# Describe a specific cluster for events and status
kubectl describe cluster <cluster-name> -n <namespace>
```

The cluster transitions through `Setting up primary` → `Recovering` → `Cluster in healthy state`. Recovery time depends on the size of the backup and WAL replay volume.

### Step 4.5 — Verify Data After Recovery

```bash
kubectl exec -it <cluster-name>-1 -n <namespace> -- psql -U postgres
```

```sql
\l         -- list databases
\dt        -- list tables
SELECT COUNT(*) FROM <key_table>;
```

---

## Phase 5: Reconcile Monitoring

With infrastructure ready and PVCs restored via Velero, bring up the monitoring stack:

```bash
flux reconcile kustomization monitoring-production --with-source
flux get kustomizations monitoring-production --watch
```

This deploys (all in the `monitoring` namespace):

| Component | Description |
|-----------|-------------|
| Prometheus | Metrics collection — data re-scraped automatically from targets |
| Grafana | Dashboards and alerts — configure once after cluster is up |
| Loki | Log aggregation — logs will be re-collected as workloads come back online |
| Alloy | Log/metric collection agent |
| Uptime Kuma | Uptime monitoring — trivial to reconfigure monitors |

---

## Phase 6: Reconcile Applications

With infrastructure, databases, and monitoring in place, allow Flux to reconcile all remaining applications:

```bash
flux resume kustomization apps-production
flux reconcile kustomization apps-production --with-source
flux get kustomizations apps-production --watch
```

Applications in namespaces restored by Velero (Phase 3) will find their PVCs already `Bound`. Applications backed by CNPG databases recovered in Phase 4 will connect to their restored databases. The remaining stateless services (e.g. `commafeed`, `coder`, `life-in-the-uk-quiz`, `litellm`) will be deployed fresh from Git; their databases are recovered via CNPG barman.

---

## Verification Checklist

After all phases are complete, verify the cluster health:

```bash
# All pods running (no Pending/CrashLoopBackOff)
kubectl get pods -A | grep -v -E 'Running|Completed'

# All CNPG clusters healthy
kubectl get cluster -A

# All Flux kustomizations ready
flux get kustomizations

# Velero restore status
velero restore get

# All PVCs bound
kubectl get pvc -A | grep -v Bound

# Certificate health
kubectl get certificates -A

# Ingress routes
kubectl get ingressroute -A
```

---

## Troubleshooting

### External Secrets not syncing

Check that `azure-sp-secret` exists in the `external-secrets` namespace with the correct keys (`ClientID`, `ClientSecret`). Then force a sync on the affected ExternalSecret:

```bash
kubectl get externalsecret -A
kubectl annotate externalsecret -n <namespace> <name> \
  force-sync=$(date +%s) --overwrite
```

### CNPG cluster stuck in `Recovering`

Check cluster events and the primary pod logs:

```bash
kubectl describe cluster <cluster-name> -n <namespace>
kubectl logs <cluster-name>-1 -n <namespace> -c postgres
```

Common causes:
- The `ObjectStore` secret (barman SAS token) has not been synced by ESO yet
- The barman backup does not contain a full base backup — check WAL archive completeness:
  ```bash
  kubectl exec -it <cluster-name>-1 -n <namespace> -- \
    barman-cloud-backup-list --format json \
    <azure-blob-path> <server-name>
  ```

### Velero restore fails for PVCs

Velero backs up PVC/PV object manifests; actual volume data is preserved on the NAS. If a PVC is restored but shows `Pending`, check that the `synology-retain` storage class is available and the Synology CSI driver is running:

```bash
kubectl get storageclass
kubectl get pods -n synology-csi
```

If the PV was using a static `volumeName` reference, ensure the PV manifest was restored and the NAS volume still exists. Re-apply the PV/PVC manually if Velero's restore missed them:

```bash
kubectl apply -f kubernetes/apps/<app>/base/pvc.yaml
```
